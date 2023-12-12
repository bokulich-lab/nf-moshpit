ARG QIIME_VERSION=2023.9

FROM quay.io/qiime2/core:$QIIME_VERSION

ARG QIIME_VERSION
ARG TYPES_VERSION=2023.9
ARG ASSEMBLY_VERSION=2023.9
ARG MOSHPIT_VERSION=2023.9

RUN echo "QIIME_VERSION=$QIIME_VERSION TYPES_VERSION=$TYPES_VERSION ASSEMBLY_VERSION=$ASSEMBLY_VERSION MOSHPIT_VERSION=$MOSHPIT_VERSION"
RUN apt-get update && apt-get install uuid-runtime

RUN conda install mamba -n base -c conda-forge -c defaults
RUN mamba env update -n qiime2-$QIIME_VERSION -f https://data.qiime2.org/distro/shotgun/qiime2-shotgun-2023.9-py38-linux-conda.yml
RUN mamba install -y -n qiime2-$QIIME_VERSION \
    -c https://packages.qiime2.org/qiime2/$QIIME_VERSION/shotgun/staged \
    -c bioconda -c conda-forge -c default \
    sourmash altair && \
    mamba run -n qiime2-$QIIME_VERSION pip install https://github.com/dib-lab/q2-sourmash/archive/master.zip

# this is a magical workaround to avoid running "vdb-config -i"
# https://github.com/ncbi/sra-tools/issues/291
RUN mkdir $HOME/.ncbi
RUN printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg

# get DBs/tools for QUAST
RUN mamba run -n qiime2-$QIIME_VERSION quast-download-silva
RUN mamba run -n qiime2-$QIIME_VERSION quast-download-gridss

# temporarily install the patched version of QUAST
# for whatever reason, this does not work with pip directly - need to clone first
RUN git clone https://github.com/misialq/quast.git /tmp/quast
WORKDIR /tmp/quast
RUN git checkout issue-230 && mamba run -n qiime2-$QIIME_VERSION pip install .

# temporarily update q2-moshpit/q2-types-genomics/q2-types to the most recent version
RUN git clone https://github.com/qiime2/q2-types.git /tmp/q2-types
WORKDIR /tmp/q2-types
RUN git checkout 8a0e191 && mamba run -n qiime2-$QIIME_VERSION pip install .

RUN git clone https://github.com/bokulich-lab/q2-types-genomics.git /tmp/q2-types-genomics
WORKDIR /tmp/q2-types-genomics
RUN git checkout 22fd9a3 && mamba run -n qiime2-$QIIME_VERSION pip install .

RUN git clone https://github.com/bokulich-lab/q2-moshpit.git /tmp/q2-moshpit
WORKDIR /tmp/q2-moshpit
RUN git checkout 3c1c8d6 && mamba run -n qiime2-$QIIME_VERSION pip install .

WORKDIR /data

RUN mamba run -n qiime2-$QIIME_VERSION qiime dev refresh-cache
