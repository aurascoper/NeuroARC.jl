# src/rules/geyser.jl
# Implementation of ArcGeyserRule and cast_geyser_beams with parallax intersection support

"""
    ArcGeyserRule <: AbstractGridRule

Deterministic ray-projection, wavefront expansion, and parallax triangulation rule
casting directed beams from emitter landmark cells until reaching boundary walls
or obstacle colors.

If `intersection_color >= 0`, cells where multiple beams intersect (parallax nodes)
are painted with `intersection_color`.
"""
struct ArcGeyserRule <: AbstractGridRule
    emitter_color::Int8
    beam_color::Int8            # -1 means inherit emitter color
    directions::Symbol          # :cardinal, :diagonal, :all8, :up, :down, :left, :right
    barrier_colors::Vector{Int8}
    stop_at_barrier::Bool
    intersection_color::Int8    # -1 means standard overwrite, >= 0 paints parallax intersection
end

function ArcGeyserRule(emitter_color::Integer=1;
                       beam_color::Integer=-1,
                       directions::Symbol=:cardinal,
                       barrier_colors::Vector{<:Integer}=Int8[],
                       stop_at_barrier::Bool=true,
                       intersection_color::Integer=-1)
    ArcGeyserRule(Int8(emitter_color), Int8(beam_color), directions,
                  Int8.(barrier_colors), stop_at_barrier, Int8(intersection_color))
end

function _get_direction_offsets(dir::Symbol)::Vector{Tuple{Int,Int}}
    if dir === :cardinal
        return [(-1, 0), (1, 0), (0, -1), (0, 1)]
    elseif dir === :diagonal
        return [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    elseif dir === :all8
        return [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
    elseif dir === :up
        return [(-1, 0)]
    elseif dir === :down
        return [(1, 0)]
    elseif dir === :left
        return [(0, -1)]
    elseif dir === :right
        return [(0, 1)]
    else
        throw(ArgumentError("Unknown directions symbol: $dir"))
    end
end

"""
    cast_geyser_beams(grid::Union{GridState, AbstractMatrix{<:Integer}};
                      emitter_color::Integer=1,
                      beam_color::Integer=-1,
                      directions::Symbol=:cardinal,
                      barrier_colors::Vector{<:Integer}=Int8[],
                      stop_at_barrier::Bool=true,
                      intersection_color::Integer=-1)::GridState

Executes deterministic ray casting from all cells matching `emitter_color`.
Detects parallax ray intersections where beams cross when `intersection_color >= 0`.
"""
function cast_geyser_beams(grid::Union{GridState, AbstractMatrix{<:Integer}};
                           emitter_color::Integer=1,
                           beam_color::Integer=-1,
                           directions::Symbol=:cardinal,
                           barrier_colors::Vector{<:Integer}=Int8[],
                           stop_at_barrier::Bool=true,
                           intersection_color::Integer=-1)::GridState
    cells = grid isa GridState ? copy(grid.cells) : Matrix{Int8}(grid)
    rows, cols = size(cells)
    e_col = Int8(emitter_color)
    b_col = beam_color < 0 ? e_col : Int8(beam_color)
    i_col = Int8(intersection_color)
    barriers = Set{Int8}(Int8.(barrier_colors))

    # Find emitter cells
    emitters = Tuple{Int,Int}[]
    for r in 1:rows, c in 1:cols
        if cells[r, c] == e_col
            push!(emitters, (r, c))
        end
    end

    result = copy(cells)
    coverage = zeros(Int, rows, cols)
    offsets = _get_direction_offsets(directions)

    for (r0, c0) in emitters
        for (dr, dc) in offsets
            r = r0 + dr
            c = c0 + dc
            while 1 <= r <= rows && 1 <= c <= cols
                # Check for barrier collision
                if cells[r, c] in barriers
                    break
                end
                # Stop if hitting another emitter
                if cells[r, c] == e_col
                    break
                end

                coverage[r, c] += 1
                if i_col >= 0 && coverage[r, c] > 1
                    result[r, c] = i_col
                else
                    result[r, c] = b_col
                end

                r += dr
                c += dc
            end
        end
    end

    return GridState(result)
end

function apply_rule(rule::ArcGeyserRule, input::GridState)::GridState
    return cast_geyser_beams(
        input;
        emitter_color=rule.emitter_color,
        beam_color=rule.beam_color,
        directions=rule.directions,
        barrier_colors=rule.barrier_colors,
        stop_at_barrier=rule.stop_at_barrier,
        intersection_color=rule.intersection_color
    )
end
