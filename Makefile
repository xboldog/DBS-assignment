.PHONY: all build clean

all: build clean

build:
	cd src && pdflatex -interaction=nonstopmode -halt-on-error report.tex && pdflatex -interaction=nonstopmode -halt-on-error report.tex

clean:
	powershell -NoProfile -Command "Remove-Item -Force -ErrorAction SilentlyContinue src/*.aux,src/*.bbl,src/*.blg,src/*.log,src/*.out,src/*.toc,src/*.run.xml,src/*.bcf,src/*.fls,src/*.fdb_latexmk"
