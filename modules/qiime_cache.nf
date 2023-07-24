process CACHE_STORE {
    conda params.condaEnvPath

    input:
    path artifact
    val key

    output:
    path "${params.qiime2CacheDir}", stageAs: 'qiime2CacheDir'

    script:
    """
    qiime tools cache-store \
      --cache ${params.qiime2CacheDir} \
      --artifact-path ${artifact} \
      --key ${key}
    """
}

process CACHE_FETCH {
    conda params.condaEnvPath
    storeDir params.storeDir

    input:
    val key
    val artifact_name

    output:
    path "${artifact_name}.qza"

    script:
    """
    qiime tools cache-fetch \
      --cache ${params.qiime2CacheDir} \
      --output-path "${artifact_name}.qza" \
      --key ${key}
    """
}
