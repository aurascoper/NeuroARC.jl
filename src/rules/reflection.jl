# src/rules/reflection.jl
# Implementation of MarkerLineReflectionRule and reflect_through_marker

"""
    MarkerLineReflectionRule <: AbstractGridRule

Applies point-inversion or axis reflection of 8-connected foreground objects
across 4-connected marker cell clusters.
"""
struct MarkerLineReflectionRule <: AbstractGridRule
    marker_color::Int8
    axis_candidate::Symbol # :auto, :point, :horizontal, :vertical
    marker_cells::Vector{Tuple{Int,Int}}
end

function MarkerLineReflectionRule(marker_color::Integer=2;
                                  axis_candidate::Symbol=:auto,
                                  marker_cells::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[])
    MarkerLineReflectionRule(Int8(marker_color), axis_candidate, marker_cells)
end

"""
    reflect_through_marker(grid::Union{GridState, AbstractMatrix{<:Integer}};
                           marker_color::Integer=2,
                           axis_candidate::Symbol=:auto,
                           marker_cells::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[])::GridState

Authoritative implementation of marker reflection semantics translated from `kaggle_modules/dsl.py:10308`.
"""
function reflect_through_marker(grid::Union{GridState, AbstractMatrix{<:Integer}};
                                marker_color::Integer=2,
                                axis_candidate::Symbol=:auto,
                                marker_cells::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[])::GridState
    cells = grid isa GridState ? copy(grid.cells) : Matrix{Int8}(grid)
    rows, cols = size(cells)
    bg = detect_background(cells)
    m_color = Int8(marker_color)

    # 1. Determine marker groups
    groups = if !isempty(marker_cells)
        [copy(marker_cells)]
    else
        extract_marker_groups_4(cells, m_color)
    end

    if isempty(groups)
        return GridState(cells)
    end

    # 2. Extract foreground objects (8-connected components excluding bg and marker_color)
    objects = extract_components_8(cells, bg; exclude_colors=Int8[m_color])
    if isempty(objects)
        return GridState(cells)
    end

    result = copy(cells)

    # 3. For each marker group, associate nearest object and reflect
    for mkr_group in groups
        isempty(mkr_group) && continue

        mkr_rows = sort(unique(first.(mkr_group)))
        mkr_cols = sort(unique(last.(mkr_group)))
        is_single = length(mkr_group) == 1
        is_horizontal = length(mkr_rows) == 1
        is_vertical = length(mkr_cols) == 1

        # Nearest object association via minimum Manhattan distance
        best_obj = nothing
        best_dist = typemax(Int)
        for obj in objects
            min_d = typemax(Int)
            for (mr, mc) in mkr_group, (or, oc) in obj.cells
                d = abs(mr - or) + abs(mc - oc)
                if d < min_d
                    min_d = d
                end
            end
            if min_d < best_dist
                best_dist = min_d
                best_obj = obj
            end
        end

        best_obj === nothing && continue

        # Determine reflection mode
        mode = if axis_candidate != :auto
            axis_candidate
        elseif is_single
            :point
        elseif is_vertical
            :vertical
        elseif is_horizontal
            :horizontal
        else
            h = maximum(mkr_rows) - minimum(mkr_rows) + 1
            w = maximum(mkr_cols) - minimum(mkr_cols) + 1
            (h > w) ? :vertical : :horizontal
        end

        # Reflect object cells
        if mode == :point
            mr, mc = mkr_group[1]
            for (r, c) in best_obj.cells
                nr = 2 * mr - r
                nc = 2 * mc - c
                if 1 <= nr <= rows && 1 <= nc <= cols
                    result[nr, nc] = best_obj.color
                end
            end
        elseif mode == :vertical
            # Vertical marker line acts as mirror along vertical column mc_axis, reflecting horizontally
            mc_axis = mkr_cols[1]
            for (r, c) in best_obj.cells
                nr = r
                nc = 2 * mc_axis - c
                if 1 <= nr <= rows && 1 <= nc <= cols
                    result[nr, nc] = best_obj.color
                end
            end
        elseif mode == :horizontal
            # Horizontal marker line acts as mirror along horizontal row mr_axis, reflecting vertically
            mr_axis = mkr_rows[1]
            for (r, c) in best_obj.cells
                nr = 2 * mr_axis - r
                nc = c
                if 1 <= nr <= rows && 1 <= nc <= cols
                    result[nr, nc] = best_obj.color
                end
            end
        end
    end

    return GridState(result)
end

function apply_rule(rule::MarkerLineReflectionRule, input::GridState)::GridState
    return reflect_through_marker(input;
                                  marker_color=rule.marker_color,
                                  axis_candidate=rule.axis_candidate,
                                  marker_cells=rule.marker_cells)
end

(rule::AbstractGridRule)(input::GridState) = apply_rule(rule, input)
(rule::AbstractGridRule)(input::AbstractMatrix{<:Integer}) = apply_rule(rule, GridState(input))
apply_rule(rule::AbstractGridRule, input::AbstractMatrix{<:Integer}) = apply_rule(rule, GridState(input))

