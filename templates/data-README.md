# Put your data here

This folder is empty on purpose. It is where the deposits for {{dataset}} go if
you want them **inside** the project.

You need your own licensed copy — nothing in this download contains any study
data, and none is fetched.

## Option (a) — put the data in here

Copy or move your deposit folders into this folder, so that you end up with:

```
{{project}}/
  run.R
  data/
    {{lookup}}        <- must be at this level
    {{sample_wave}}/
      ...tab
    ...
```

The one thing that matters is that **`{{lookup}}` sits directly in this
folder**. If you unzip a download and it arrives wrapped in its own folder —
`data/{{root}}/{{lookup}}` — that is fine too; `run.R` looks one level down and
says so when it does.

## Option (b) — point at data you already have

Licensed microdata is large and there is no reason to copy it. Leave this
folder empty, open `run.R`, and set:

```r
DATA_DIR <- "~/{{root}}"
```

`run.R` also honours the `{{env}}` environment variable, if you already set
that for other work.

## This project never writes to your data

Every read goes through `R/lib/io.R`, which only ever opens files for reading.
Results are written to `output/`, next to `run.R` — never in here.
