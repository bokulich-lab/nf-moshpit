ARG BASE_IMAGE_TAG=latest
FROM quay.io/qiime2/tiny:${BASE_IMAGE_TAG}

ARG PREV_VERSION
ARG NEXT_VERSION
ENV PREV_ENV_NAME=qiime2-tiny-${PREV_VERSION}
ENV NEW_ENV_NAME=moshpit-${NEXT_VERSION}

RUN conda install -n base -c conda-forge mamba

RUN conda rename -n ${PREV_ENV_NAME} ${NEW_ENV_NAME}

# Install dependencies using mamba and pip
RUN wget https://raw.githubusercontent.com/qiime2/distributions/dev/latest/passed/qiime2-moshpit-ubuntu-latest-conda.yml
RUN mamba env update -n ${NEW_ENV_NAME} -f qiime2-moshpit-ubuntu-latest-conda.yml

RUN mamba install -n ${NEW_ENV_NAME} -c bioconda -c conda-forge -c defaults fastp multiqc

RUN mamba run -n ${NEW_ENV_NAME} pip install git+https://github.com/bokulich-lab/q2-fastp.git

RUN mamba run -n ${NEW_ENV_NAME} qiime dev refresh-cache
