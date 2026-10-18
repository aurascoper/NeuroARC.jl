#!/usr/bin/env bash
# manuscript/build_pdf.sh
# Build NeuroARC.jl manuscript PDF and verify text cleanliness
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "Building NeuroARC.jl Manuscript PDF"
echo "Directory: $SCRIPT_DIR"
echo "================================================================================"

# Render Graphviz DOT figures to PDF if dot is available
if command -v dot &>/dev/null; then
  echo "Rendering Graphviz DOT figures..."
  dot -Tpdf figures/figure_b1_typed_grafting.dot -o figures/figure_b1_typed_grafting.pdf
  dot -Tpdf figures/figure_b2_agent_execution.dot -o figures/figure_b2_agent_execution.pdf
  dot -Tsvg figures/figure_b1_typed_grafting.dot -o figures/figure_b1_typed_grafting.svg
  dot -Tsvg figures/figure_b2_agent_execution.dot -o figures/figure_b2_agent_execution.svg
else
  echo "Graphviz 'dot' not found; using existing PDF/SVG figures."
fi

# Compile LaTeX to PDF via tectonic or xelatex
if command -v tectonic &>/dev/null; then
  echo "Compiling main.tex via tectonic..."
  tectonic main.tex
elif command -v xelatex &>/dev/null; then
  echo "Compiling main.tex via xelatex..."
  xelatex -interaction=nonstopmode main.tex
  bibtex main
  xelatex -interaction=nonstopmode main.tex
  xelatex -interaction=nonstopmode main.tex
elif command -v pdflatex &>/dev/null; then
  echo "Compiling main.tex via pdflatex..."
  pdflatex -interaction=nonstopmode main.tex
  bibtex main
  pdflatex -interaction=nonstopmode main.tex
  pdflatex -interaction=nonstopmode main.tex
else
  echo "Error: Neither tectonic, xelatex, nor pdflatex found on PATH." >&2
  exit 1
fi

echo "Extracting layout text from main.pdf..."
if command -v pdftotext &>/dev/null; then
  pdftotext -layout main.pdf main.txt
  echo "Auditing text cleanliness on extracted text..."
  python3 ../test/check_text_clean.py .
else
  echo "pdftotext not found; checking LaTeX source files only..."
  python3 ../test/check_text_clean.py .
fi

echo "================================================================================"
echo "Manuscript PDF Build Complete: $(pwd)/main.pdf"
echo "================================================================================"
