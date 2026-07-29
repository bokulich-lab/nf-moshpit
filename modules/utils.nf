#!/usr/bin/env nextflow

def extractCacheDataKey(yamlFile) {
    def matcher = yamlFile.readLines().findResult { line ->
        def hit = (line =~ /^\s*data\s*:\s*["']?([^"'\s]+)["']?\s*$/)
        hit.matches() ? hit[0][1] : null
    }

    if (matcher) {
        return matcher
    }

    def preview = yamlFile.readLines().take(5).join('\n')
    throw new Exception("Could not parse 'data' key from cache key YAML: ${yamlFile}. First lines:\n${preview}")
}

// Function to parse YAML file, extract UUID, construct path, and get directory size in GB
def getDirectorySizeInGB(inputPath, basePath) {
    def yamlFile = new java.io.File(inputPath)
    if (!yamlFile.exists()) {
        throw new Exception("Cache key YAML does not exist: ${inputPath}")
    }

    def uuid = extractCacheDataKey(yamlFile)
    
    // Construct the final path by appending UUID to base path
    def concatenatedPath = java.nio.file.Paths.get(basePath).resolve(uuid).toString()
    
    // Calculate directory size in GB
    def directory = new java.io.File(concatenatedPath)
    def sizeInBytes = 0L
    if (directory.exists() && directory.isDirectory()) {
        directory.eachFileRecurse { file ->
            if (file.isFile()) {
                sizeInBytes += file.length()
            }
        }
    }
    def sizeInGB = sizeInBytes / (1024.0 * 1024.0 * 1024.0)
    def sizeInGBRoundedUp = Math.ceil(1.2 * sizeInGB) as int
    
    return [
        uuid: uuid,
        concatenatedPath: concatenatedPath,
        sizeInGB: sizeInGB.round(2),
        sizeInGBRoundedUp: sizeInGBRoundedUp
    ]
}
