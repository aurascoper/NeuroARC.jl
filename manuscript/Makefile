.PHONY: all pdf clean check

all: pdf check

pdf:
	./build_pdf.sh

check:
	python3 ../test/check_text_clean.py .

clean:
	rm -f *.aux *.bbl *.blg *.log *.out *.toc *.txt
