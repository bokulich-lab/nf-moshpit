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

process EXPORT_ARTIFACT_METADATA {
    cpus 1
    memory { 2.GB * task.attempt }
    time { 1.h * task.attempt }
    scratch true
    errorStrategy 'retry'
    maxRetries 3
    tag "${sample_id}: ${context}"
    publishDir "${params.outputDir}/provenance/metadata", mode: 'copy'

    input:
    tuple val(sample_id), val(context), path(metadata_key)

    output:
    tuple val(sample_id), val(context), path("${metadata_key.getName()}.tsv"), emit: metadata
    path "${metadata_key.getName()}.metadata-source.qza", emit: source
    path "${metadata_key.getName()}.metadata.json", emit: record

    script:
    archive_dir = file("${params.outputDir}/provenance/metadata").toAbsolutePath()
    """
    export_metadata.py \
      --cache '${params.q2TemporaryCachesDir}/${sample_id}' \
      --key '${metadata_key.getName()}' \
      --archive-dir '${archive_dir}' \
      --sample-id '${sample_id}' \
      --context '${context}'
    """
}
