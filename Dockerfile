ARG BASE_IMAGE_TAG=latest
FROM quay.io/qiime2/tiny:${BASE_IMAGE_TAG}

ARG VERSION
ENV ENV_NAME=qiime2-tiny-${VERSION}

RUN conda install -n base -c conda-forge mamba

# Install dependencies using mamba and pip
RUN wget https://raw.githubusercontent.com/qiime2/distributions/dev/latest/passed/qiime2-moshpit-ubuntu-latest-conda.yml
RUN mamba env update -n ${ENV_NAME} -f qiime2-moshpit-ubuntu-latest-conda.yml

RUN mamba install -n ${ENV_NAME} -c bioconda -c conda-forge -c defaults fastp multiqc

RUN mamba run -n ${ENV_NAME} pip install \
    git+https://github.com/bokulich-lab/q2-annotate.git \
    git+https://github.com/bokulich-lab/q2-fastp.git

# this is a magical workaround to avoid running "vdb-config -i"
# https://github.com/ncbi/sra-tools/issues/291
RUN mkdir $HOME/.ncbi
RUN printf '/LIBS/GUID = "%s"\n' `uuidgen` > $HOME/.ncbi/user-settings.mkfg

# get DBs/tools for QUAST
RUN mamba run -n ${ENV_NAME} quast-download-silva
RUN mamba run -n ${ENV_NAME} quast-download-gridss

RUN mamba run -n ${ENV_NAME} qiime dev refresh-cache
