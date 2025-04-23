FROM continuumio/miniconda3:latest

ARG EPOCH
ARG DISTRO
ARG ENVIRONMENT

ENV PATH /opt/conda/envs/${DISTRO}-${EPOCH}/bin:$PATH
ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8
ENV MPLBACKEND agg
ENV UNIFRAC_USE_GPU N
ENV HOME /home/qiime2
ENV XDG_CONFIG_HOME /home/qiime2

RUN mkdir /home/qiime2
WORKDIR /home/qiime2

RUN conda update -q -y conda \
    && conda install -c conda-forge -q -y wget mamba \
    && apt-get install -y procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN wget -O ${ENVIRONMENT}-env.yml https://raw.githubusercontent.com/qiime2/distributions/dev/${EPOCH}/${DISTRO}/${ENVIRONMENT}/qiime2-${DISTRO}-ubuntu-latest-conda.yml

RUN mamba env create -n ${DISTRO}-${EPOCH} --file ${ENVIRONMENT}-env.yml \
    && mamba install -n ${DISTRO}-${EPOCH} -c bioconda -c conda-forge -c defaults fastp multiqc \
    && mamba run -n ${DISTRO}-${EPOCH} pip install git+https://github.com/bokulich-lab/q2-fastp.git \
    && mamba clean -a -y \
    && chmod -R a+rwx /opt/conda \
    && rm ${ENVIRONMENT}-env.yml

RUN /bin/bash -c "source activate ${DISTRO}-${EPOCH}"
ENV CONDA_PREFIX /opt/conda/envs/${DISTRO}-${EPOCH}/
RUN qiime dev refresh-cache
RUN echo "source activate ${DISTRO}-${EPOCH}" >> $HOME/.bashrc
RUN echo "source tab-qiime" >> $HOME/.bashrc

# Important: let any UID modify these directories so that
# `docker run -u UID:GID` works
RUN chmod -R a+rwx /home/qiime2
