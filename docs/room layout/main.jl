using GLMakie
NLEDS = 198
index2α(i) = rad2deg(rem2pi(2π*(i + 0.5)/NLEDS - (π + π/2), RoundNearest))
α2index(α) = round(UInt8, clamp(NLEDS*(rem(α + π + π/2, 2π)/2π) - 0.5, 0, NLEDS - 1))

fig = Figure()
ax = Axis(fig[1,1], aspect = DataAspect(), limits = (0, 500, 0, 300))
c = Point2f(130, 150)
r = 100
# poly!(ax, Circle(c, r), color = :transparent, strokecolor = :black, strokewidth = 1)
poly!(ax, Rect(260, 230, 500-260-100 - 10, 70), color = :transparent, strokecolor = :black, strokewidth = 1)
text!(ax, 260 + (500-260-100 - 10)/2, 230 + 35, text = "desk", align = (:center, :center))
vlines!(ax, 260, color = :black)
arc!(ax, Point2f(500, 300), 100, π, 1.5π, color = :black)
text!(ax, 10, 290, text = "tent", align = (:left, :top))
text!(ax, Point2f(500, 300) + 50*Vec2(reverse(sincospi(-0.75)))..., 250, text = "door", align = (:center, :center))
text!(ax, [c + 1.1r*Vec(reverse(sincospi(i))) for i in 0:0.5:1.5], text = ["E", "N", "W", "S"], align = (:center, :center))
hidedecorations!(ax)
for i in 0:NLEDS - 1
    θ = index2α(i)
    scatter!(ax, c + r*Vec2f(reverse(sincosd(θ))), color = (:black, 0.2))
end
for α in range(-180, step = 45, stop = 180)[1:end-1]
    θ = α + 90
    text!(ax, c + 0.9r*Vec2f(reverse(sincosd(θ))), text = string(round(Int, α)), align = (:center, :center))
end

save("azimuths.png", fig)
