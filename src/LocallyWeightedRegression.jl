# ------------------------------------------------------------------
# Licensed under the ISC License. See LICENCE in the project root.
# ------------------------------------------------------------------

module LocallyWeightedRegression

using GeoStatsBase

using LinearAlgebra
using NearestNeighbors
using StaticArrays
using Distances
using Variography

import GeoStatsBase: solve

export LocalWeightRegress

"""
    LocalWeightRegress(var₁=>param₁, var₂=>param₂, ...)

Locally weighted regression (LOESS) estimation solver.

## Parameters

* `neighbors` - Number of neighbors (default to all data locations)
* `variogram` - A variogram defined in Variography.jl (default to `ExponentialVariogram()`)
* `distance`  - A distance defined in Distances.jl (default to `Euclidean()`)

### References

Cleveland 1979. *Robust Locally Weighted Regression and Smoothing Scatterplots*
"""
@estimsolver LocalWeightRegress begin
  @param neighbors = nothing
  @param variogram = ExponentialVariogram()
  @param distance = Euclidean()
end

function solve(problem::EstimationProblem, solver::LocalWeightRegress)
  # retrieve problem info
  pdata = data(problem)
  pdomain = domain(problem)

  # result for each variable
  μs = []; σs = []

  for covars in covariables(problem, solver)
    for var in covars.names
      # get user parameters
      varparams = covars.params[(var,)]

      # get variable type
      V = variables(problem)[var]

      # get valid data for variable
      X, z = valid(pdata, var)

      # number of data points for variable
      ndata = length(z)

      @assert ndata > 0 "estimation requires data"

      # allocate memory
      varμ = Vector{V}(undef, npoints(pdomain))
      varσ = Vector{V}(undef, npoints(pdomain))

      # fit search tree
      M = varparams.distance
      if M isa NearestNeighbors.MinkowskiMetric
        tree = KDTree(X, M)
      else
        tree = BruteTree(X, M)
      end

      # determine number of nearest neighbors to use
      k = varparams.neighbors == nothing ? ndata : varparams.neighbors

      @assert k ≤ ndata "number of neighbors must be smaller or equal to number of data points"

      # determine kernel (or weight) function
      γ = varparams.variogram
      kern(x, y) = sill(γ) - γ(x, y)

      # pre-allocate memory for coordinates
      x = MVector{ndims(pdomain),coordtype(pdomain)}(undef)

      # estimation loop
      for location in LinearPath(pdomain)
        coordinates!(x, pdomain, location)

        inds, dists = knn(tree, x, k)

        Xₗ = [ones(eltype(X), k) X[:,inds]']
        zₗ = view(z, inds)

        Wₗ = Diagonal([kern(x, view(X,:,j)) for j in inds])

        # weighted least-squares
        θₗ = Xₗ'*Wₗ*Xₗ \ Xₗ'*Wₗ*zₗ

        # add intercept term to estimation location
        xₗ = [one(eltype(x)), x...]

        # linear combination of response values
        rₗ = Wₗ*Xₗ*(Xₗ'*Wₗ*Xₗ\xₗ)

        varμ[location] = θₗ ⋅ xₗ
        varσ[location] = norm(rₗ)
      end

      push!(μs, var => varμ)
      push!(σs, var => varσ)
    end
  end

  EstimationSolution(pdomain, Dict(μs), Dict(σs))
end

end
