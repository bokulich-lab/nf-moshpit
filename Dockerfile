ARG QIIME_VERSION=2022.11

FROM quay.io/qiime2/core:$QIIME_VERSION

ARG QIIME_VERSION
ARG TYPES_VERSION=${QIIME_VERSION}
ARG ASSEMBLY_VERSION=${QIIME_VERSION}
ARG MOSHPIT_VERSION=${QIIME_VERSION}

RUN echo "QIIME_VERSION=$QIIME_VERSION TYPES_VERSION=$TYPES_VERSION ASSEMBLY_VERSION=$ASSEMBLY_VERSION MOSHPIT_VERSION=$MOSHPIT_VERSION" 
RUN apt-get update && apt-get install uuid-runtime

RUN conda install mamba -n base -c conda-forge
RUN mamba install -y -n qiime2-$QIIME_VERSION \
    -c https://packages.qiime2.org/qiime2/$QIIME_VERSION/tested \
    -c bioconda -c conda-forge -c default \
    q2-types-genomics==$TYPES_VERSION q2-assembly==$ASSEMBLY_VERSION q2-moshpit==$MOSHPIT_VERSION \
    q2-checkm q2-fondue q2-taxa
RUN mamba run -n qiime2-$QIIME_VERSION qiime dev refresh-cache

# this is a magical workaround to avoid running "vdb-config -i"
# https://github.com/ncbi/sra-tools/issues/291
RUN mkdir $HOME/.ncbi
RUN printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg
