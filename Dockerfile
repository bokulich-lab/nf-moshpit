FROM quay.io/qiime2/core:2022.11

RUN conda install mamba -n base -c conda-forge
RUN mamba install -y -n qiime2-2022.11 \
    -c https://packages.qiime2.org/qiime2/2022.11/tested \
    -c bioconda -c conda-forge -c default \
    q2-types-genomics q2-assembly q2-moshpit q2-checkm
RUN mamba run -n base qiime dev refresh-cache
