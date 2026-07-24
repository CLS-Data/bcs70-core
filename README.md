# BCS70 Core Harmonisation

This repository provides **R scripts** that harmonise the multiple sweeps of the [1970 British Cohort Study](https://cls.ucl.ac.uk/cls-studies/1970-british-cohort-study/) into a single tidy dataset, so analysts can get straight to research rather than recoding.

This work is being done with human-in-the-loop AI development. Zero study data is exposed to any LLM. The AI workflow only has access to publicly available metadata and dummy files for each dataset, with absolutely no real data content.

The output will be modular R scripts that can be run on the actual data. The actual folder and file structure can be recreated by following this repository:

- [CLS-Data/make-directories-bcs70 (shuffle-plus)](https://github.com/CLS-Data/make-directories-bcs70/tree/shuffle-plus)
