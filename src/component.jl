# src/component.jl
# Connected component analysis, background detection, and marker extraction

"""
    detect_background(cells::AbstractMatrix{<:Integer})::Int8

Identifies the background color as the most frequent color in the grid.
Ties are broken deterministically by choosing the lowest color index (0..9).
"""
function detect_background(cells::AbstractMatrix{<:Integer})::Int8
    counts = zeros(Int, 10)
    for c in cells
        if 0 <= c <= 9
            counts[c + 1] += 1
        end
    end
    max_count = maximum(counts)
    for c in 0:9
        if counts[c + 1] == max_count
            return Int8(c)
        end
    end
    return Int8(0)
end

"""
    compute_palette(cells::AbstractMatrix{<:Integer})::UInt16

Returns a bitmask over colors 0..9 present in the grid.
"""
function compute_palette(cells::AbstractMatrix{<:Integer})::UInt16
    mask = UInt16(0)
    for c in cells
        if 0 <= c <= 9
            mask |= (UInt16(1) << c)
        end
    end
    return mask
end

"""
    count_holes(cells::AbstractMatrix{<:Integer}, comp_cells::Vector{Tuple{Int,Int}}, bbox::NTuple{4,Int})::Int

Counts 4-connected enclosed background cavities (holes) completely surrounded by the component.
"""
function count_holes(cells::AbstractMatrix{<:Integer}, comp_cells::Vector{Tuple{Int,Int}}, bbox::NTuple{4,Int})::Int
    rmin, cmin, rmax, cmax = bbox
    H = rmax - rmin + 1
    W = cmax - cmin + 1
    if H <= 2 || W <= 2
        return 0
    end

    # Mask within bounding box
    is_comp = zeros(Bool, H, W)
    for (r, c) in comp_cells
        is_comp[r - rmin + 1, c - cmin + 1] = true
    end

    # Padded grid with 1-cell border for exterior flood-fill
    pH = H + 2
    pW = W + 2
    visited_ext = zeros(Bool, pH, pW)

    queue = Tuple{Int,Int}[(1, 1)]
    visited_ext[1, 1] = true

    while !isempty(queue)
        cr, cc = popfirst!(queue)
        for (dr, dc) in ((-1, 0), (1, 0), (0, -1), (0, 1))
            nr, nc = cr + dr, cc + dc
            if 1 <= nr <= pH && 1 <= nc <= pW && !visited_ext[nr, nc]
                # If within original box, can only traverse if not part of component
                is_interior = (2 <= nr <= pH - 1) && (2 <= nc <= pW - 1)
                can_traverse = !is_interior || !is_comp[nr - 1, nc - 1]
                if can_traverse
                    visited_ext[nr, nc] = true
                    push!(queue, (nr, nc))
                end
            end
        end
    end

    # Holes are non-component cells inside bbox not reached by exterior flood fill
    hole_mask = zeros(Bool, H, W)
    for r in 1:H, c in 1:W
        if !is_comp[r, c] && !visited_ext[r + 1, c + 1]
            hole_mask[r, c] = true
        end
    end

    # Count 4-connected components of hole cells
    hole_visited = zeros(Bool, H, W)
    hole_count = 0
    for r in 1:H, c in 1:W
        if hole_mask[r, c] && !hole_visited[r, c]
            hole_count += 1
            h_queue = Tuple{Int,Int}[(r, c)]
            hole_visited[r, c] = true
            while !isempty(h_queue)
                hr, hc = popfirst!(h_queue)
                for (dr, dc) in ((-1, 0), (1, 0), (0, -1), (0, 1))
                    nhr, nhc = hr + dr, hc + dc
                    if 1 <= nhr <= H && 1 <= nhc <= W && hole_mask[nhr, nhc] && !hole_visited[nhr, nhc]
                        hole_visited[nhr, nhc] = true
                        push!(h_queue, (nhr, nhc))
                    end
                end
            end
        end
    end

    return hole_count
end

"""
    extract_components_8(cells::AbstractMatrix{<:Integer}, bg_color::Int8; exclude_colors::Vector{Int8}=Int8[])::Vector{ConnectedComponent}

Extracts monochromatic 8-connected components for cells where color != bg_color and color not in exclude_colors.
"""
function extract_components_8(cells::AbstractMatrix{<:Integer}, bg_color::Int8; exclude_colors::Vector{Int8}=Int8[])::Vector{ConnectedComponent}
    rows, cols = size(cells)
    visited = zeros(Bool, rows, cols)
    components = ConnectedComponent[]
    comp_id = 1

    for r in 1:rows, c in 1:cols
        val = Int8(cells[r, c])
        if val != bg_color && !(val in exclude_colors) && !visited[r, c]
            c_cells = Tuple{Int,Int}[]
            queue = Tuple{Int,Int}[(r, c)]
            visited[r, c] = true

            while !isempty(queue)
                cr, cc = popfirst!(queue)
                push!(c_cells, (cr, cc))

                for dr in -1:1, dc in -1:1
                    (dr == 0 && dc == 0) && continue
                    nr, nc = cr + dr, cc + dc
                    if 1 <= nr <= rows && 1 <= nc <= cols && !visited[nr, nc] && Int8(cells[nr, nc]) == val
                        visited[nr, nc] = true
                        push!(queue, (nr, nc))
                    end
                end
            end

            sort!(c_cells)
            rmin = minimum(first.(c_cells))
            cmin = minimum(last.(c_cells))
            rmax = maximum(first.(c_cells))
            cmax = maximum(last.(c_cells))
            bbox = (rmin, cmin, rmax, cmax)
            is_border = (rmin == 1 || cmin == 1 || rmax == rows || cmax == cols)
            holes = count_holes(cells, c_cells, bbox)

            push!(components, ConnectedComponent(comp_id, val, c_cells, bbox, is_border, holes))
            comp_id += 1
        end
    end

    return components
end

"""
    extract_marker_groups_4(cells::AbstractMatrix{<:Integer}, marker_color::Int8)::Vector{Vector{Tuple{Int,Int}}}

Extracts 4-connected marker groups of the specified marker color.
"""
function extract_marker_groups_4(cells::AbstractMatrix{<:Integer}, marker_color::Int8)::Vector{Vector{Tuple{Int,Int}}}
    rows, cols = size(cells)
    visited = zeros(Bool, rows, cols)
    groups = Vector{Tuple{Int,Int}}[]

    for r in 1:rows, c in 1:cols
        if Int8(cells[r, c]) == marker_color && !visited[r, c]
            g_cells = Tuple{Int,Int}[]
            queue = Tuple{Int,Int}[(r, c)]
            visited[r, c] = true

            while !isempty(queue)
                cr, cc = popfirst!(queue)
                push!(g_cells, (cr, cc))

                for (dr, dc) in ((-1, 0), (1, 0), (0, -1), (0, 1))
                    nr, nc = cr + dr, cc + dc
                    if 1 <= nr <= rows && 1 <= nc <= cols && !visited[nr, nc] && Int8(cells[nr, nc]) == marker_color
                        visited[nr, nc] = true
                        push!(queue, (nr, nc))
                    end
                end
            end

            sort!(g_cells)
            push!(groups, g_cells)
        end
    end

    return groups
end

"""
    GridState(cells::AbstractMatrix{<:Integer}; extract_components::Bool=true)

Convenience constructor for `GridState` calculating palette bitmask, background color,
and extracting 8-connected components.
"""
function GridState(cells::AbstractMatrix{<:Integer}; extract_components::Bool=true)
    rows, cols = size(cells)
    c_matrix = Matrix{Int8}(cells)
    palette = compute_palette(c_matrix)
    bg = detect_background(c_matrix)
    comps = extract_components ? extract_components_8(c_matrix, bg) : ConnectedComponent[]
    return GridState(c_matrix, rows, cols, palette, bg, comps)
end
