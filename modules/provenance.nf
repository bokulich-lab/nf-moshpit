process CHECKPOINT_DEREP_MAGS {
    cpus 1
    memory { 4.GB * task.attempt }
    time { 2.h * task.attempt }
    scratch true
    errorStrategy 'retry'
    maxRetries 3
    publishDir "${params.outputDir}/provenance", mode: 'copy', pattern: '*.{qza,json}'

    input:
    path original_key

    output:
    path checkpoint_key, emit: bins_derep
    path "${checkpoint_key}.upstream.qza", emit: upstream
    path "${checkpoint_key}.qza", emit: checkpoint
    path "${checkpoint_key}.json", emit: record

    script:
    checkpoint_key = "${original_key.getName()}_checkpoint_v1"
    archive_dir = file("${params.outputDir}/provenance").toAbsolutePath()
    """
    checkpoint_artifact.py \
      --cache '${params.q2cacheDir}' \
      --input-key '${original_key.getName()}' \
      --output-key '${checkpoint_key}' \
      --archive-dir '${archive_dir}' \
      --run-id '${params.runId}'
    """
}
