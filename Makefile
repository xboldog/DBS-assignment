.PHONY: all build clean

all: build clean

build:
	cd src && pdflatex report.tex && bibtex report && pdflatex report.tex && pdflatex report.tex

clean:
	cd src && rm -f *.aux *.bbl *.blg *.log *.out *.toc *.run.xml *.bcf