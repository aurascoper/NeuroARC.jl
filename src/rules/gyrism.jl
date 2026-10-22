# src/rules/gyrism.jl
# Implementation of ArcGyrismRule and circulate_gyre

"""
    ArcGyrismRule <: AbstractGridRule

Rotational circulation and vortex permutation primitive rotating cells or
concentric rings around a designated centroid marker.
"""
struct ArcGyrismRule <: AbstractGridRule
    center_color::Int8     # Landmark color for rotation center (-1 for grid center)
    angle_degrees::Int     # 90, 180, 270
    clockwise::Bool
end

function ArcGyrismRule(center_color::Integer=-1; angle_degrees::Integer=90, clockwise::Bool=true)
    ArcGyrismRule(Int8(center_color), Int(angle_degrees), clockwise)
end

"""
    circulate_gyre(grid::Union{GridState, AbstractMatrix{<:Integer}};
                   center_color::Integer=-1,
                   angle_degrees::Integer=90,
                   clockwise::Bool=true)::GridState

Performs rotational circulation around the specified center.
"""
function circulate_gyre(grid::Union{GridState, AbstractMatrix{<:Integer}};
                        center_color::Integer=-1,
                        angle_degrees::Integer=90,
                        clockwise::Bool=true)::GridState
    cells = grid isa GridState ? copy(grid.cells) : Matrix{Int8}(grid)
    rows, cols = size(cells)
    bg = detect_background(cells)

    # Determine center of rotation
    c_row, c_col = 0.0, 0.0
    if center_color >= 0
        c_cells = Tuple{Int,Int}[]
        for r in 1:rows, c in 1:cols
            if cells[r, c] == Int8(center_color)
                push!(c_cells, (r, c))
            end
        end
        if !isempty(c_cells)
            c_row = sum(first.(c_cells)) / length(c_cells)
            c_col = sum(last.(c_cells)) / length(c_cells)
        else
            c_row = (rows + 1) / 2.0
            c_col = (cols + 1) / 2.0
        end
    else
        c_row = (rows + 1) / 2.0
        c_col = (cols + 1) / 2.0
    end

    # Effective rotation factor
    k = mod(div(angle_degrees, 90), 4)
    if !clockwise
        k = mod(4 - k, 4)
    end

    result = copy(cells)
    if k == 0
        return GridState(result)
    end

    # Pass 1: Clear all movable foreground cells in target buffer first so rotating
    # multi-pixel polyominoes never overwrite newly placed pixels in scan order.
    c_col_int8 = Int8(center_color)
    for r in 1:rows, c in 1:cols
        val = cells[r, c]
        if val != bg && (center_color < 0 || val != c_col_int8)
            result[r, c] = bg
        end
    end

    # Pass 2: Place rotated foreground cells from unmodified source grid
    for r in 1:rows, c in 1:cols
        val = cells[r, c]
        if val != bg && (center_color < 0 || val != c_col_int8)
            # Offset relative to center
            dr = r - c_row
            dc = c - c_col

            # Rotate: k * 90 deg clockwise
            # (dr, dc) -> (dc, -dr) for 90 deg CW
            new_dr, new_dc = if k == 1
                (dc, -dr)
            elseif k == 2
                (-dr, -dc)
            elseif k == 3
                (-dc, dr)
            else
                (dr, dc)
            end

            nr = round(Int, c_row + new_dr)
            nc = round(Int, c_col + new_dc)

            if 1 <= nr <= rows && 1 <= nc <= cols
                result[nr, nc] = val
            end
        end
    end

    return GridState(result)
end

function apply_rule(rule::ArcGyrismRule, input::GridState)::GridState
    return circulate_gyre(
        input;
        center_color=rule.center_color,
        angle_degrees=rule.angle_degrees,
        clockwise=rule.clockwise
    )
end
