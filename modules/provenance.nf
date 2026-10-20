process DEDUPLICATE_PROVENANCE {
    cpus 1
    memory 2.GB
    time {
        def requested = (params.provenance_dedup.baseTime as nextflow.util.Duration) +
            (params.provenance_dedup.timePerSample as nextflow.util.Duration) * sample_count
        def maximum = params.provenance_dedup.maxTime as nextflow.util.Duration
        requested > maximum ? maximum : requested
    }
    scratch true
    cache false
    errorStrategy 'terminate'
    maxRetries 0
    tag params.runId
    publishDir params.traceDir, mode: 'copy'

    input:
    val all_tasks_finished
    val sample_count
    val cache_roots
    path dedup_script, stageAs: 'deduplicate_provenance.py'

    output:
    path "${params.runId}-provenance-dedup-*.jsonl", emit: audit
    path "${params.runId}-provenance-dedup-summary.json", emit: summary

    script:
    def quote = { value -> "'" + value.toString().replace("'", "'\"'\"'") + "'" }
    def roots = cache_roots.collect { quote(it) }.join(' ')
    def report_prefix = quote("${params.runId}-provenance-dedup-")
    def summary_name = quote("${params.runId}-provenance-dedup-summary.json")
    def flags = []
    if (params.provenance_dedup.ignoreMtime) flags << '--ignore-mtime'
    if (params.provenance_dedup.ignoreLustreLayout) flags << '--ignore-lustre-layout'
    """
    set -euo pipefail
    echo "Deduplicating provenance for ${sample_count} input samples; time limit: ${task.time}"
    # A fresh audit name also permits rerunning this noncached task with -resume.
    report=${report_prefix}"\$(python3 -c 'import uuid; print(uuid.uuid4())').jsonl"
    python3 deduplicate_provenance.py ${roots} \
      --apply \
      --report "\$report" \
      --scratch-dir "\$PWD" \
      --max-links ${params.provenance_dedup.maxLinks} \
      ${flags.join(' ')} > ${summary_name}
    cat ${summary_name}
    """
}
