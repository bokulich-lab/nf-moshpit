// Resolve from configuration wherever bins or cache keys are selected.
// Do not mutate params: module parameter snapshots must agree.
def effectivePrimaryBinner(binning) {
    binning.das_tool.enabled ? 'das_tool' : binning.primary?.toString()?.trim()
}

def evaluateBinnerBusco(binning) {
    binning.qc.busco.enabled && !binning.das_tool.enabled
}
