ARG QIIME_VERSION=2023.2

FROM quay.io/qiime2/core:$QIIME_VERSION

ARG QIIME_VERSION
ARG TYPES_VERSION=2023.2
ARG ASSEMBLY_VERSION=2023.2
ARG MOSHPIT_VERSION=2023.2

RUN echo "QIIME_VERSION=$QIIME_VERSION TYPES_VERSION=$TYPES_VERSION ASSEMBLY_VERSION=$ASSEMBLY_VERSION MOSHPIT_VERSION=$MOSHPIT_VERSION" 
RUN apt-get update && apt-get install uuid-runtime

RUN conda install "mamba<=1.4" -n base -c conda-forge -c defaults
RUN mamba install -y -n qiime2-$QIIME_VERSION \
    -c https://packages.qiime2.org/qiime2/2023.5/tested \
    -c bioconda -c conda-forge -c default \
    qiime2==2023.5.0.dev0+4.gfe49136 \
    q2cli==2023.5.0.dev0+2.g259ffd6 \
    q2-types-genomics==$TYPES_VERSION \
    q2-assembly==$ASSEMBLY_VERSION \
    q2-moshpit==$MOSHPIT_VERSION \
    q2-checkm q2-fondue q2-taxa q2-cutadapt q2-demux

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
WORKDIR /data

RUN mamba run -n qiime2-$QIIME_VERSION qiime dev refresh-cache
