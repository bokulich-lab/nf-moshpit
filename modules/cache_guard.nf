import groovy.json.JsonOutput

// Run synchronously before any process/storeDir shortcut can reuse a marker.
def protectPersistentCaches(boolean finish = false) {
    def snapshot = File.createTempFile('moshpit-params-', '.json')
    try {
        snapshot.text = JsonOutput.toJson(params)
        def command = ['python3', "${projectDir}/bin/cache_guard.py", '--params', snapshot.absolutePath, '--source', projectDir.toString()]
        if (finish) command << '--finish'
        def task = new ProcessBuilder(command.collect { it.toString() }).redirectErrorStream(true).start()
        def output = task.inputStream.text
        if (task.waitFor() != 0) throw new IllegalStateException(output.trim())
    } finally {
        snapshot.delete()
    }
}
