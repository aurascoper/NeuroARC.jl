"""
UCSF ChimeraX attribute (.defattr) serializer.

Converts multi-omics residue-level scores (e.g., JIVE joint loadings,
conservation scores, evolutionary selection statistics) into ChimeraX-native
definition attribute files (.defattr) and command automation scripts (.cxc).
"""

from pathlib import Path
from typing import Dict, List, Optional, Union
import numpy as np


def export_chimerax_defattr(
    residue_scores: Union[Dict[int, float], List[float], np.ndarray],
    attribute_name: str,
    output_path: Union[str, Path],
    chain: str = "A",
    start_residue: int = 1,
    recipient: str = "residues",
    match_mode: str = "1-to-1",
    comment: Optional[str] = None
) -> Path:
    """
    Export residue-level numerical values to a ChimeraX .defattr file.

    Args:
        residue_scores: Dict mapping residue number (int) -> score (float),
                        or list/array where index 0 corresponds to start_residue.
        attribute_name: Identifier for attribute inside ChimeraX (no spaces).
        output_path: File destination ending in .defattr.
        chain: Protein chain identifier (e.g., 'A').
        start_residue: 1-based start residue index if array/list is passed.
        recipient: Target level ('residues' or 'atoms').
        match_mode: ChimeraX matching mode ('1-to-1' or 'any').
        comment: Optional descriptive metadata header comment.

    Returns:
        Path to generated .defattr file.
    """
    out_file = Path(output_path)
    out_file.parent.mkdir(parents=True, exist_ok=True)

    # Normalize residue_scores to Dict[int, float]
    if isinstance(residue_scores, (list, np.ndarray)):
        score_dict = {
            start_residue + idx: float(val)
            for idx, val in enumerate(residue_scores)
            if not np.isnan(val)
        }
    elif isinstance(residue_scores, dict):
        score_dict = {
            int(k): float(v)
            for k, v in residue_scores.items()
            if not np.isnan(v)
        }
    else:
        raise TypeError("residue_scores must be a dict, list, or numpy ndarray.")

    clean_attr = attribute_name.replace(" ", "_")

    lines = []
    lines.append(f"# UCSF ChimeraX attribute definition file")
    if comment:
        lines.append(f"# {comment}")
    lines.append(f"attribute: {clean_attr}")
    lines.append(f"match mode: {match_mode}")
    lines.append(f"recipient: {recipient}")
    lines.append("")

    # Assign values per residue
    # Format: /<chain>:<res_num> <tab> <value>
    for res_num in sorted(score_dict.keys()):
        val = score_dict[res_num]
        lines.append(f"/{chain}:{res_num}\t{val:.6f}")

    content = "\n".join(lines) + "\n"
    out_file.write_text(content, encoding="utf-8")
    return out_file


def generate_chimerax_script(
    pdb_path: Union[str, Path],
    defattr_path: Union[str, Path],
    attribute_name: str,
    output_script_path: Union[str, Path],
    palette: str = "blue:white:red",
    chain: str = "A"
) -> Path:
    """
    Generate a ChimeraX command script (.cxc) to load structure and color by attribute.

    Args:
        pdb_path: Path to target PDB structure.
        defattr_path: Path to .defattr attribute file.
        attribute_name: Name of attribute defined in defattr file.
        output_script_path: Path to write the .cxc script.
        palette: ChimeraX color palette specification.
        chain: Chain to highlight.

    Returns:
        Path to generated .cxc script.
    """
    out_script = Path(output_script_path)
    out_script.parent.mkdir(parents=True, exist_ok=True)

    clean_attr = attribute_name.replace(" ", "_")
    abs_pdb = Path(pdb_path).resolve()
    abs_attr = Path(defattr_path).resolve()

    commands = [
        f"# ChimeraX automated visualization script",
        f"open {abs_pdb}",
        f"open {abs_attr}",
        f"style / {chain} cartoons",
        f"color byattribute {clean_attr} /{chain} palette {palette}",
        f"view",
        f"lighting soft",
        f"# Save presentation image if needed:",
        f"# save rendered_{clean_attr}.png transparentBackground true",
    ]

    out_script.write_text("\n".join(commands) + "\n", encoding="utf-8")
    return out_script
