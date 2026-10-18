# src/bridge/json_parser.jl
# Lightweight dependency-free JSON parser and proposal compiler for Julia dispatch

mutable struct JSONParserState
    src::String
    pos::Int
    len::Int
end

function skip_whitespace!(st::JSONParserState)
    while st.pos <= st.len
        ch = st.src[st.pos]
        if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r'
            st.pos += 1
        else
            break
        end
    end
end

function parse_json_value(st::JSONParserState)::Any
    skip_whitespace!(st)
    if st.pos > st.len
        error("Unexpected end of JSON input")
    end

    ch = st.src[st.pos]
    if ch == '{'
        return parse_json_object(st)
    elseif ch == '['
        return parse_json_array(st)
    elseif ch == '"'
        return parse_json_string(st)
    elseif ch == 't' || ch == 'f'
        return parse_json_bool(st)
    elseif ch == 'n'
        return parse_json_null(st)
    elseif ch == '-' || ('0' <= ch <= '9')
        return parse_json_number(st)
    else
        error("Unexpected character in JSON: '$ch' at position $(st.pos)")
    end
end

function parse_json_object(st::JSONParserState)::Dict{String, Any}
    st.pos += 1 # skip '{'
    obj = Dict{String, Any}()
    skip_whitespace!(st)
    if st.pos <= st.len && st.src[st.pos] == '}'
        st.pos += 1
        return obj
    end

    while true
        skip_whitespace!(st)
        if st.pos > st.len || st.src[st.pos] != '"'
            error("Expected string key in object at position $(st.pos)")
        end
        key = parse_json_string(st)

        skip_whitespace!(st)
        if st.pos > st.len || st.src[st.pos] != ':'
            error("Expected ':' after object key at position $(st.pos)")
        end
        st.pos += 1 # skip ':'

        val = parse_json_value(st)
        obj[key] = val

        skip_whitespace!(st)
        if st.pos <= st.len && st.src[st.pos] == ','
            st.pos += 1 # skip ','
        elseif st.pos <= st.len && st.src[st.pos] == '}'
            st.pos += 1 # skip '}'
            break
        else
            error("Expected ',' or '}' in object at position $(st.pos)")
        end
    end

    return obj
end

function parse_json_array(st::JSONParserState)::Vector{Any}
    st.pos += 1 # skip '['
    arr = Any[]
    skip_whitespace!(st)
    if st.pos <= st.len && st.src[st.pos] == ']'
        st.pos += 1
        return arr
    end

    while true
        val = parse_json_value(st)
        push!(arr, val)

        skip_whitespace!(st)
        if st.pos <= st.len && st.src[st.pos] == ','
            st.pos += 1 # skip ','
        elseif st.pos <= st.len && st.src[st.pos] == ']'
            st.pos += 1 # skip ']'
            break
        else
            error("Expected ',' or ']' in array at position $(st.pos)")
        end
    end

    return arr
end

function parse_json_string(st::JSONParserState)::String
    st.pos += 1 # skip opening '"'
    buf = IOBuffer()

    while st.pos <= st.len
        ch = st.src[st.pos]
        st.pos += 1
        if ch == '"'
            return String(take!(buf))
        elseif ch == '\\'
            if st.pos > st.len
                error("Unterminated escape sequence in string")
            end
            esc_ch = st.src[st.pos]
            st.pos += 1
            if esc_ch == '"' || esc_ch == '\\' || esc_ch == '/'
                write(buf, esc_ch)
            elseif esc_ch == 'b'
                write(buf, '\b')
            elseif esc_ch == 'f'
                write(buf, '\f')
            elseif esc_ch == 'n'
                write(buf, '\n')
            elseif esc_ch == 'r'
                write(buf, '\r')
            elseif esc_ch == 't'
                write(buf, '\t')
            elseif esc_ch == 'u'
                if st.pos + 3 > st.len
                    error("Incomplete unicode escape at position $(st.pos)")
                end
                hex_str = st.src[st.pos:st.pos+3]
                st.pos += 4
                write(buf, Char(parse(UInt32, hex_str, base=16)))
            else
                write(buf, esc_ch)
            end
        else
            write(buf, ch)
        end
    end

    error("Unterminated string in JSON")
end

function parse_json_number(st::JSONParserState)::Union{Int, Float64}
    start_pos = st.pos
    is_float = false
    if st.src[st.pos] == '-'
        st.pos += 1
    end
    while st.pos <= st.len && ('0' <= st.src[st.pos] <= '9')
        st.pos += 1
    end
    if st.pos <= st.len && st.src[st.pos] == '.'
        is_float = true
        st.pos += 1
        while st.pos <= st.len && ('0' <= st.src[st.pos] <= '9')
            st.pos += 1
        end
    end
    if st.pos <= st.len && (st.src[st.pos] == 'e' || st.src[st.pos] == 'E')
        is_float = true
        st.pos += 1
        if st.pos <= st.len && (st.src[st.pos] == '+' || st.src[st.pos] == '-')
            st.pos += 1
        end
        while st.pos <= st.len && ('0' <= st.src[st.pos] <= '9')
            st.pos += 1
        end
    end

    num_str = st.src[start_pos:st.pos-1]
    if is_float
        return parse(Float64, num_str)
    else
        return parse(Int, num_str)
    end
end

function parse_json_bool(st::JSONParserState)::Bool
    if st.src[st.pos:min(st.pos+3, st.len)] == "true"
        st.pos += 4
        return true
    elseif st.src[st.pos:min(st.pos+4, st.len)] == "false"
        st.pos += 5
        return false
    else
        error("Invalid boolean at position $(st.pos)")
    end
end

function parse_json_null(st::JSONParserState)::Nothing
    if st.src[st.pos:min(st.pos+3, st.len)] == "null"
        st.pos += 4
        return nothing
    else
        error("Invalid null at position $(st.pos)")
    end
end

"""
    parse_json(str::AbstractString)::Any

Parses a JSON string into Julia structures.
"""
function parse_json(str::AbstractString)::Any
    st = JSONParserState(String(str), 1, ncodeunits(str))
    res = parse_json_value(st)
    skip_whitespace!(st)
    if st.pos <= st.len
        error("Extra characters after JSON root element at position $(st.pos)")
    end
    return res
end

"""
    parse_json_file(filepath::AbstractString)::Any

Reads and parses a JSON file.
"""
function parse_json_file(filepath::AbstractString)::Any
    return parse_json(read(filepath, String))
end

"""
    compile_rule(proposal::Dict{String, Any})::AbstractGridRule

Compiles a validated rule proposal envelope into an instantiated `AbstractGridRule`.
Coordinates from JSON (row0, column0) are 0-based and converted to Julia 1-based indexing.
"""
function compile_rule(proposal::Dict{String, Any})::AbstractGridRule
    rule_type = get(proposal, "rule_type", "")

    if rule_type == "MarkerLineReflectionRule"
        marker_color = Int8(2)
        axis_candidate = :auto
        marker_cells = Tuple{Int,Int}[]

        hypotheses = get(proposal, "parameter_hypotheses", Any[])
        for h in hypotheses
            name = get(h, "name", "")
            kind = get(h, "kind", "")
            val = get(h, "value", nothing)

            if name == "marker_color" || kind == "color"
                marker_color = Int8(val)
            elseif name == "axis_candidate" || (kind == "text" && val in ["vertical", "horizontal", "point", "auto"])
                axis_candidate = Symbol(val)
            elseif name == "marker_cells" || kind == "coordinates0"
                if val isa Vector
                    for coord in val
                        if coord isa Dict
                            r0 = Int(get(coord, "row0", 0))
                            c0 = Int(get(coord, "column0", 0))
                            push!(marker_cells, (r0 + 1, c0 + 1))
                        end
                    end
                end
            end
        end

        return MarkerLineReflectionRule(marker_color; axis_candidate=axis_candidate, marker_cells=marker_cells)
    elseif rule_type == "GeodesicBarrierFloodRule"
        return GeodesicBarrierFloodRule()
    elseif rule_type == "CorridorWireTraceRule"
        return CorridorWireTraceRule()
    elseif rule_type == "PeriodicStampWithPriorityRule"
        return PeriodicStampWithPriorityRule()
    elseif rule_type == "ExactCoverPolyominoRule"
        return ExactCoverPolyominoRule()
    else
        throw(ArgumentError("Unknown or unsupported rule family: '$rule_type'"))
    end
end

"""
    compile_rule_from_file(filepath::AbstractString)::AbstractGridRule

Parses and compiles a rule proposal from a file path.
"""
function compile_rule_from_file(filepath::AbstractString)::AbstractGridRule
    proposal = parse_json_file(filepath)
    return compile_rule(proposal)
end
