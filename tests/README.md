Run these checks in a QIIME 2 environment with `q2-types` and Nextflow available:

```bash
NEXTFLOW=/path/to/nextflow NXF_SYNTAX_PARSER=v1 \
  python -B -m unittest discover -s tests -v
```

The workflow checks run the actual Nextflow modules with synthetic inputs and
lightweight fixtures for external binning/filtering commands. They check sample
and lineage matching, cleanup ordering (including all MAGs being rejected),
TSV routing for BUSCO and read-count filters, and checkpoint resume. They do not
run BUSCO, MetaBAT2, or the full HPC/container pipeline.

The artifact checks use the public QIIME API and its synthetic test plugin.
They validate payload/type/format preservation, source archives, typed metadata
round-trips and threshold selection, UUID links, and the resulting ancestry.
Framework tests skip when QIIME is unavailable; Nextflow tests skip when neither
`NEXTFLOW` nor a `nextflow` executable is available. The scripts and all task
outputs use temporary directories. The test processes enable QIIME's synthetic
plugin mode rather than loading every plugin in the environment.
