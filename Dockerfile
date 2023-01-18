FROM quay.io/qiime2/core:2022.11
ARG TYPES_VERSION=2022.11
ARG ASSEMBLY_VERSION=2022.11
ARG MOSHPIT_VERSION=2022.11

RUN apt-get update && apt-get install uuid-runtime

RUN conda install mamba -n base -c conda-forge
RUN mamba install -y -n qiime2-2022.11 \
    -c https://packages.qiime2.org/qiime2/2022.11/tested \
    -c bioconda -c conda-forge -c default \
    q2-types-genomics==$TYPES_VERSION q2-assembly==$ASSEMBLY_VERSION q2-moshpit==$MOSHPIT_VERSION q2-checkm q2-fondue
RUN mamba run -n qiime2-2022.11 qiime dev refresh-cache

# this is a magical workaround to avoid running "vdb-config -i"
# https://github.com/ncbi/sra-tools/issues/291
RUN mkdir $HOME/.ncbi
RUN printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg
