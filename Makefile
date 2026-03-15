.PHONY: all build clean

all: build clean

build:
	cd src && pdflatex main.tex && bibtex main && pdflatex main.tex && pdflatex main.tex

clean:
	cd src && rm -f *.aux *.bbl *.blg *.log *.out *.toc *.run.xml *.bcf