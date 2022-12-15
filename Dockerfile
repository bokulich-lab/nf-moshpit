FROM quay.io/qiime2/core:2022.8
ARG TYPES_VERSION=2022.11
ARG ASSEMBLY_VERSION=2022.11
ARG MOSHPIT_VERSION=2022.11

RUN conda install mamba -n base -c conda-forge
RUN mamba install -y -n qiime2-2022.8 \
    -c https://packages.qiime2.org/qiime2/2022.11/tested \
    -c https://packages.qiime2.org/qiime2/2022.8/tested \
    -c bioconda -c conda-forge -c default \
    q2-types-genomics==$TYPES_VERSION q2-assembly==$ASSEMBLY_VERSION q2-moshpit==$MOSHPIT_VERSION q2-checkm q2-fondue
RUN mamba run -n qiime2-2022.8 qiime dev refresh-cache
RUN mamba run -n qiime2-2022.8 vdb-config -i & disown
