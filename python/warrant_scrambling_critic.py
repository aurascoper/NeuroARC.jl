"""
ARC-AGI-2 Coevolutionary Warrant-Scrambling & Informative LOO Critic (Pure Python + NumPy)
Strictly zero em-dashes and zero en-dashes.
"""

from typing import Callable, Dict, List, Set, Tuple

Grid = List[List[int]]


def copy_grid(grid: Grid) -> Grid:
    return [row[:] for row in grid]


def grid_shape(grid: Grid) -> Tuple[int, int]:
    return (len(grid), len(grid[0]) if grid else 0)


def rot90_ccw(grid: Grid, k: int = 1) -> Grid:
    k = k % 4
    g = copy_grid(grid)
    for _ in range(k):
        h, w = grid_shape(g)
        g = [[g[r][w - 1 - c] for r in range(h)] for c in range(w)]
    return g


def fliplr_grid(grid: Grid) -> Grid:
    return [ list(reversed(row)) for row in grid ]


def dihedral_transform(grid: Grid, op_id: int) -> Grid:
    """Applies one of the 8 dihedral group D4 symmetries (0..7)."""
    g = rot90_ccw(grid, k=(op_id % 4))
    return fliplr_grid(g) if (op_id >= 4) else g


def inverse_dihedral_transform(grid: Grid, op_id: int) -> Grid:
    """Inverts dihedral_transform(grid, op_id)."""
    g = fliplr_grid(grid) if (op_id >= 4) else copy_grid(grid)
    return rot90_ccw(g, k=(4 - (op_id % 4)) % 4)


def permute_colors(grid: Grid, color_map: Dict[int, int]) -> Grid:
    """Applies a bijective color scrambling map simultaneously across a grid."""
    return [[color_map.get(val, val) for val in row] for row in grid]


def scramble_in_grid_legend_pair(
    x: Grid,
    y: Grid,
    legend_bbox: Tuple[int, int, int, int],
    color_a: int,
    color_b: int,
) -> Tuple[Grid, Grid]:
    """
    ARC-AGI-2 Legend Warrant Scrambler:
    Swaps symbolic colors `color_a <-> color_b` inside both the in-grid instruction
    legend (`legend_bbox = (r0, r1, c0, c1)`) and the workspace/output grids.
    """
    cmap = {color_a: color_b, color_b: color_a}
    return permute_colors(x, cmap), permute_colors(y, cmap)


def evaluate_warrant_under_scrambling(
    program_fn: Callable[[Grid], Grid],
    train_pairs: List[Tuple[Grid, Grid]],
    fixed_colors: Set[int] = frozenset({0}),
    test_rotations: bool = True,
    ast_node_count: int = 1,
    alpha_mdl: float = 0.02,
) -> dict:
    """
    Evaluates an ARC-AGI-2 candidate program on:
      1. Exact training pair fit.
      2. Color-scrambling equivariance warrant: P(pi(X)) == pi(P(X)).
      3. Spatial dihedral D4 equivariance warrant: P(g(X)) == g(P(X)).
      4. Coevolutionary Aesthetic Prior (Minimum Description Length penalty).
    """
    import math

    exact_matches = 0
    color_set: Set[int] = set()
    for x, y in train_pairs:
        for grid in (x, y):
            for row in grid:
                for val in row:
                    if val not in fixed_colors:
                        color_set.add(val)
        try:
            pred = program_fn(copy_grid(x))
            if pred == y:
                exact_matches += 1
        except Exception:
            pass
    train_acc = exact_matches / max(len(train_pairs), 1)
    active_colors = sorted(color_set)

    color_warrant_trials = 0
    color_warrant_passes = 0
    candidate_cmaps: List[Dict[int, int]] = []
    if len(active_colors) >= 2:
        shifted = active_colors[1:] + active_colors[:1]
        candidate_cmaps.append({c: s for c, s in zip(active_colors, shifted)})
    if len(active_colors) >= 1:
        unused_colors = [c for c in range(1, 10) if c not in fixed_colors and c not in color_set]
        if unused_colors:
            candidate_cmaps.append(
                {c: unused_colors[idx % len(unused_colors)] for idx, c in enumerate(active_colors)}
            )

    for cmap in candidate_cmaps:
        for x, y in train_pairs:
            color_warrant_trials += 1
            try:
                x_scr = permute_colors(x, cmap)
                y_scr_expected = permute_colors(y, cmap)
                y_scr_pred = program_fn(x_scr)
                if y_scr_pred == y_scr_expected:
                    color_warrant_passes += 1
            except Exception:
                pass
    color_warrant = (
        color_warrant_passes / color_warrant_trials if color_warrant_trials > 0 else 1.0
    )

    spatial_warrant_trials = 0
    spatial_warrant_passes = 0
    if test_rotations:
        for op_id in (1, 2, 4):
            for x, y in train_pairs:
                spatial_warrant_trials += 1
                try:
                    x_rot = dihedral_transform(x, op_id)
                    y_rot_expected = dihedral_transform(y, op_id)
                    y_rot_pred = program_fn(x_rot)
                    if y_rot_pred == y_rot_expected:
                        spatial_warrant_passes += 1
                except Exception:
                    pass
    spatial_warrant = (
        spatial_warrant_passes / spatial_warrant_trials if spatial_warrant_trials > 0 else 1.0
    )

    mdl_score = math.exp(-alpha_mdl * max(ast_node_count - 1, 0))
    composite_fitness = (
        0.50 * train_acc
        + 0.25 * color_warrant
        + 0.15 * spatial_warrant
        + 0.10 * mdl_score
    )

    return {
        "train_accuracy": train_acc,
        "color_scrambling_warrant": color_warrant,
        "spatial_scrambling_warrant": spatial_warrant,
        "aesthetic_mdl_score": float(mdl_score),
        "composite_fitness": float(composite_fitness),
        "is_warranted_generalizer": (train_acc == 1.0 and color_warrant == 1.0),
    }


def evaluate_arc_agi2_loo_and_warrant_gate(
    synthesize_on_subset_fn: Callable[[List[Tuple[Grid, Grid]]], Callable[[Grid], Grid]],
    demo_pairs: List[Tuple[Grid, Grid]],
    legend_bbox: Tuple[int, int, int, int] = (0, 2, 0, 2),
    swappable_colors: Tuple[int, int] = (1, 2),
) -> dict:
    """
    Enforces both:
      1. Section C2 Informative Leave-One-Out (LOO) Criterial Gate.
      2. Coevolutionary Warrant-Scrambling Gate under in-grid legend swaps.
    """
    n_demos = len(demo_pairs)
    if n_demos < 2:
        raise ValueError("Informative LOO gate requires at least 2 demonstration pairs")

    loo_zero_pixel_folds = 0
    warrant_scramble_passes = 0
    ca, cb = swappable_colors

    for holdout_idx in range(n_demos):
        train_subset = [pair for idx, pair in enumerate(demo_pairs) if idx != holdout_idx]
        x_val, y_val = demo_pairs[holdout_idx]

        candidate_prog = synthesize_on_subset_fn(train_subset)

        y_pred = candidate_prog(copy_grid(x_val))
        if y_pred == y_val:
            loo_zero_pixel_folds += 1

        x_scr, y_scr_expected = scramble_in_grid_legend_pair(x_val, y_val, legend_bbox, ca, cb)
        y_scr_pred = candidate_prog(x_scr)
        if y_scr_pred == y_scr_expected:
            warrant_scramble_passes += 1

    status = (
        "ACCEPTED"
        if (loo_zero_pixel_folds == n_demos and warrant_scramble_passes == n_demos)
        else "REJECTED_OVERFIT_OR_UNWARRANTED"
    )

    return {
        "verdict": status,
        "loo_folds_passed": f"{loo_zero_pixel_folds}/{n_demos}",
        "legend_warrant_folds_passed": f"{warrant_scramble_passes}/{n_demos}",
    }
