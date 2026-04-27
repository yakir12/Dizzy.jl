using GLMakie
using Distributions
using SpecialFunctions

κ2fwhm(κ) = κ ≤ log(2)/2 ? 2π : 2acos(1 − log(2)/κ)
fwhm2κ(fwhm) = log(2)/(1 - cos(fwhm/2))


pixels = 400
fig = Figure()
κ = 3
fwhm = κ2fwhm(κ)
hfwhm = round(Int, rad2deg(fwhm/2))
ymax = 1/(2π*besselix(0.0, κ))
d = VonMises(κ)
ax1 = Axis(fig[1,1], title = "κ = $κ", xlabel = "Angle (°)", ylabel = "Density", xticks = -180:90:180, limits = (-180, 180, 0, 1.1ymax), yticks = ([0, ymax/2, ymax], ["0", "h/2", "h"]), width = pixels, height = pixels)
x = range(-π, π, 101)
band!(ax1, rad2deg.(x), zeros(101), pdf.(d, x), color = (:blue, 0.3))
errorbars!(ax1, [0], [ymax/2], [hfwhm], direction = :x, whiskerwidth = 30, color = :black)
text!(ax1, 0, ymax/2, text = "FWHM ≈ $(10round(Int, rad2deg(fwhm)/10))°", align = (:center, :top))
κ = 0.3
fwhm = κ2fwhm(κ)
hfwhm = round(Int, rad2deg(fwhm/2))
ymax = 1/(2π*besselix(0.0, κ))
d = VonMises(κ)
ax2 = Axis(fig[1,2], title = "κ = $κ", xlabel = "Angle (°)", ylabel = "Density", xticks = -180:90:180, limits = (-180, 180, 0, 1.1ymax), yticks = ([0, ymax/2, ymax], ["0", "h/2", "h"]), width = pixels, height = pixels)
x = range(-π, π, 101)
band!(ax2, rad2deg.(x), zeros(101), pdf.(d, x), color = (:blue, 0.3))
errorbars!(ax2, [0], [ymax/2], [hfwhm], direction = :x, whiskerwidth = 30, color = :black)
text!(ax2, 0, ymax/2, text = "FWHM = $(10round(Int, rad2deg(fwhm)/10))°", align = (:center, :top))
hideydecorations!(ax2, grid = false, minorgrid = false, minorticks = false)
colgap!(fig.layout, pixels/8)
maxkappa = 1000
ax = Axis(fig[2,1], ylabel = "FWHM (°)", xlabel = "κ", yticks = 0:90:360, limits = (nothing, maxkappa, nothing, nothing), width = pixels, height = pixels)
κ = collect(logrange(0.001, maxkappa, 100))
sort!(push!(κ, log(2)/2))
lines!(ax, κ, rad2deg.(κ2fwhm.(κ)), color = :black)
ax = Axis(fig[2,2], ylabel = "FWHM (°)", xlabel = "κ", yticks = 0:90:360, limits = (nothing, maxkappa, nothing, nothing), width = pixels, height = pixels, xscale = log10, yscale= log10)
lines!(ax, κ, rad2deg.(κ2fwhm.(κ)), color = :black)
resize_to_layout!(fig)
save("fwhm and kappa.png", fig)



# fig = Figure()
# ax = Axis(fig[1, 1])
# κ = Observable(10.0)
# dist = @lift VonMises($κ)
# lines!(ax, dist)
# ymax = @lift 1/(2π*besselix(0.0, $κ))
# xlims!(ax, -π, π)
# on(ymax) do y
#     ylims!(ax, 0, y)
# end
# fwhm = lift(κ2fwhm, κ)
# p1 = @lift Point(-$fwhm/2, $ymax/2)
# p2 = @lift Point($fwhm/2, $ymax/2)
# lines!(ax, @lift([$p1, $p2]))
# fig
#
# kappa_iterator =  logrange(0.1, 100, 1000)
# record(fig, "fwhm3.mp4", kappa_iterator;
#         framerate = 30) do kappa
#     κ[] = kappa
# end
#
#
# fig = Figure()
# ax = Axis(fig[1,1], xlabel = "FWHM (°)", ylabel = "κ", xticks = 0:90:360, limits = (nothing, 360, 0, 10))
# fwhm = range(0, 2π, 100)
# lines!(ax, rad2deg.(fwhm), fwhm2κ.(fwhm))
#
# save("fwhm1.png", fig)
#
# fig = Figure()
# ax = Axis(fig[1,1], ylabel = "FWHM (°)", xlabel = "κ", yticks = 0:90:360, limits = (nothing, 1000, nothing, 360))
# κ = range(0.001, 1000, 10000)
# lines!(ax, κ, rad2deg.(κ2fwhm.(κ)))
#
# save("fwhm2.png", fig)
