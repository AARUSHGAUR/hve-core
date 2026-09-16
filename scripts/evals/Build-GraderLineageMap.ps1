#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Builds or checks the Vally grader-name lineage map.
.DESCRIPTION
    Pairs graders from two reachable revisions by source, stimulus, and a
    name-free behavior digest. The script fails closed on unreachable history,
    provenance drift, ambiguous pairs, semantic changes, count drift, kind
    mismatches, duplicate result keys, or output drift.
.PARAMETER RepoRoot
    Repository root. Defaults to the current Git worktree root.
.PARAMETER SourceRevision
    Reachable pre-migration revision. When omitted, reads the committed map.
.PARAMETER TargetRevision
    Reachable migrated revision. When omitted, reads the committed map.
.PARAMETER SourceProvenanceRevision
    Original reviewed pre-migration revision used for semantic verification.
.PARAMETER OutputPath
    Path to the committed lineage JSON.
.PARAMETER Check
    Verifies the committed map without changing it.
.EXAMPLE
    ./scripts/evals/Build-GraderLineageMap.ps1 -SourceRevision <sha> -TargetRevision <sha>
.EXAMPLE
    ./scripts/evals/Build-GraderLineageMap.ps1 -Check
.NOTES
    Runs via: npm run lint:eval-grader-lineage
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$SourceRevision,

    [Parameter(Mandatory = $false)]
    [string]$TargetRevision,

    [Parameter(Mandatory = $false)]
    [string]$SourceProvenanceRevision = 'ce4c686f8906288db28ccf8a1108c26e2ea52bd9',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Constants

$script:ExpectedSourceToTargetPairs = 1240
$script:ExpectedAuthoredAliases = 414
$script:ExpectedGeneratedCopies = 171
$script:GeneratedSpecPath = 'evals/agent-behavior/eval.yaml'
$script:LineageRoots = @(
    'evals/agent-behavior/stimuli',
    'evals/agent-conformance',
    'evals/baseline-equivalence'
)

#endregion Constants

#region Functions

function Resolve-LineageRepoRoot {
    <#
    .SYNOPSIS
        Resolves the repository root.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Override
    )

    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return (Resolve-Path -LiteralPath $Override).Path
    }

    $resolved = (& git rev-parse --show-toplevel 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolved)) {
        throw 'Unable to resolve the repository root.'
    }
    return $resolved
}

function Import-LineageYamlModule {
    <#
    .SYNOPSIS
        Imports the YAML parser required by the generator.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Module -Name powershell-yaml)) {
        Import-Module powershell-yaml -ErrorAction Stop
    }
}

function Invoke-LineageGit {
    <#
    .SYNOPSIS
        Invokes Git and returns output lines.
    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = @(& git -C $RepoRoot @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Arguments -join ' ')"
    }
    return $output
}

function Get-LineageSha256 {
    <#
    .SYNOPSIS
        Computes a lowercase SHA-256 digest for text.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function ConvertTo-LineageCanonicalValue {
    <#
    .SYNOPSIS
        Recursively sorts mapping keys for deterministic JSON serialization.
    .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            $ordered[$key] = ConvertTo-LineageCanonicalValue -Value $Value[$key]
        }
        return $ordered
    }

    if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-LineageCanonicalValue -Value $_ })
    }

    return $Value
}

function Get-GraderBehaviorSha256 {
    <#
    .SYNOPSIS
        Computes a grader digest that excludes only its configured name.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Grader
    )

    $withoutName = [ordered]@{}
    foreach ($key in @($Grader.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
        if ($key -eq 'name') {
            continue
        }
        $withoutName[$key] = ConvertTo-LineageCanonicalValue -Value $Grader[$key]
    }
    $canonical = $withoutName | ConvertTo-Json -Depth 100 -Compress
    return Get-LineageSha256 -Text $canonical
}

function Get-GraderResultKind {
    <#
    .SYNOPSIS
        Maps an authored grader type to its Vally result-detail kind.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$GraderType
    )

    switch ($GraderType) {
        'prompt' { return 'llm' }
        'human' { return 'human' }
        { $_ -in @('file-exists', 'file-matches', 'output-contains', 'output-matches', 'wall-time') } {
            return 'code'
        }
        default { throw "Unsupported grader type '$GraderType'." }
    }
}

function Test-AuthoredLineagePath {
    <#
    .SYNOPSIS
        Identifies canonical authored migration inputs.
    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (
        $Path -match '^evals/agent-behavior/stimuli/[^/]+\.yml$' -or
        $Path -match '^evals/agent-conformance/[^/]+/eval\.yaml$' -or
        $Path -in @(
            'evals/baseline-equivalence/baseline/eval.yaml',
            'evals/baseline-equivalence/customized/eval.yaml',
            'evals/baseline-equivalence/stimuli.yml'
        )
    )
}

function Get-LineageMigrationPaths {
    <#
    .SYNOPSIS
        Gets changed authored inputs plus the generated verification input.
    .OUTPUTS
        System.String[]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$SourceRevision,

        [Parameter(Mandatory = $true)]
        [string]$TargetRevision
    )

    $changed = Invoke-LineageGit -RepoRoot $RepoRoot -Arguments @(
        'diff', '--name-only', $SourceRevision, $TargetRevision, '--'
    )
    $paths = @($changed | Where-Object {
            (Test-AuthoredLineagePath -Path $_) -or $_ -eq $script:GeneratedSpecPath
        } | Sort-Object -Unique)

    if ($script:GeneratedSpecPath -notin $paths) {
        throw "Generated verification input '$($script:GeneratedSpecPath)' did not change."
    }
    if (@($paths | Where-Object { Test-AuthoredLineagePath -Path $_ }).Count -eq 0) {
        throw 'No authored lineage inputs changed.'
    }
    return $paths
}

function Get-LineageEvalName {
    <#
    .SYNOPSIS
        Resolves the top-level eval identity for a YAML source.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Document
    )

    if ($Document.Contains('name') -and -not [string]::IsNullOrWhiteSpace([string]$Document['name'])) {
        return [string]$Document['name']
    }
    if ($Path -like 'evals/agent-behavior/*') {
        return 'agent-behavior'
    }
    if ($Path -eq 'evals/baseline-equivalence/stimuli.yml') {
        return 'baseline-equivalence-stimuli'
    }
    throw "Cannot resolve eval name for '$Path'."
}

function Get-GraderLineageRecords {
    <#
    .SYNOPSIS
        Reads grader records from Git objects at one revision.
    .OUTPUTS
        System.Object[]
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Revision,

        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $Paths) {
        $raw = (Invoke-LineageGit -RepoRoot $RepoRoot -Arguments @('show', "${Revision}:$path")) -join "`n"
        try {
            $document = ConvertFrom-Yaml -Yaml $raw -Ordered
        }
        catch {
            throw "Failed to parse '$path' at '$Revision': $($_.Exception.Message)"
        }
        if ($document -isnot [System.Collections.IDictionary]) {
            throw "Lineage input '$path' at '$Revision' is not a YAML mapping."
        }

        $evalName = Get-LineageEvalName -Path $path -Document $document
        foreach ($stimulus in @($document['stimuli'])) {
            if ($stimulus -isnot [System.Collections.IDictionary]) {
                throw "Lineage input '$path' contains a non-mapping stimulus."
            }
            $stimulusName = [string]$stimulus['name']
            foreach ($grader in @($stimulus['graders'])) {
                if ($grader -isnot [System.Collections.IDictionary]) {
                    throw "Lineage input '$path' stimulus '$stimulusName' contains a non-mapping grader."
                }
                $graderType = [string]$grader['type']
                $name = [string]$grader['name']
                if ([string]::IsNullOrWhiteSpace($graderType) -or [string]::IsNullOrWhiteSpace($name)) {
                    throw "Lineage input '$path' stimulus '$stimulusName' has an incomplete grader."
                }
                $behaviorSha256 = Get-GraderBehaviorSha256 -Grader $grader
                $records.Add([pscustomobject]@{
                        EvalName       = $evalName
                        Source         = $path
                        Stimulus       = $stimulusName
                        GraderType     = $graderType
                        ResultKind     = Get-GraderResultKind -GraderType $graderType
                        Name           = $name
                        BehaviorSha256 = $behaviorSha256
                        PairKey        = "$path`n$stimulusName`n$behaviorSha256"
                    })
            }
        }
    }
    return @($records)
}

function Compare-GraderLineageRecords {
    <#
    .SYNOPSIS
        Pairs source and target graders and rejects ambiguous or semantic drift.
    .OUTPUTS
        System.Object[]
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$SourceRecords,

        [Parameter(Mandatory = $true)]
        [object[]]$TargetRecords
    )

    if ($SourceRecords.Count -ne $TargetRecords.Count) {
        throw "Grader count changed from $($SourceRecords.Count) to $($TargetRecords.Count)."
    }

    $sourceIndex = @{}
    foreach ($record in $SourceRecords) {
        if ($sourceIndex.ContainsKey($record.PairKey)) {
            throw "Ambiguous source grader pair '$($record.PairKey)'."
        }
        $sourceIndex[$record.PairKey] = $record
    }

    $targetIndex = @{}
    foreach ($record in $TargetRecords) {
        if ($targetIndex.ContainsKey($record.PairKey)) {
            throw "Ambiguous target grader pair '$($record.PairKey)'."
        }
        $targetIndex[$record.PairKey] = $record
    }

    $pairs = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @($sourceIndex.Keys | Sort-Object)) {
        if (-not $targetIndex.ContainsKey($key)) {
            throw "Semantic grader change or missing target pair '$key'."
        }
        $source = $sourceIndex[$key]
        $target = $targetIndex[$key]
        if ($source.GraderType -ne $target.GraderType -or $source.ResultKind -ne $target.ResultKind) {
            throw "Grader type or result kind changed for '$key'."
        }
        $pairs.Add([pscustomobject]@{ Source = $source; Target = $target })
    }
    return @($pairs)
}

function Assert-GraderLineageRevisions {
    <#
    .SYNOPSIS
        Validates revision reachability, ordering, and provenance equivalence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$SourceProvenanceRevision,

        [Parameter(Mandatory = $true)]
        [string]$SourceRevision,

        [Parameter(Mandatory = $true)]
        [string]$TargetRevision
    )

    $head = @(Invoke-LineageGit -RepoRoot $RepoRoot -Arguments @('rev-parse', 'HEAD'))[0]
    foreach ($revision in @($SourceProvenanceRevision, $SourceRevision, $TargetRevision)) {
        [void](Invoke-LineageGit -RepoRoot $RepoRoot -Arguments @('cat-file', '-e', "$revision^{commit}"))
    }
    foreach ($revision in @($SourceRevision, $TargetRevision)) {
        & git -C $RepoRoot merge-base --is-ancestor $revision $head
        if ($LASTEXITCODE -ne 0) {
            throw "Revision '$revision' is not an ancestor of replacement head '$head'."
        }
    }
    & git -C $RepoRoot merge-base --is-ancestor $SourceRevision $TargetRevision
    if ($LASTEXITCODE -ne 0) {
        throw "Source revision '$SourceRevision' is not an ancestor of target revision '$TargetRevision'."
    }

    & git -C $RepoRoot diff --quiet $SourceProvenanceRevision $SourceRevision -- @script:LineageRoots
    if ($LASTEXITCODE -eq 1) {
        throw "Source revision '$SourceRevision' does not match provenance '$SourceProvenanceRevision' for lineage inputs."
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Git failed while verifying source provenance equivalence.'
    }
}

function Get-GraderRecordSetSha256 {
    <#
    .SYNOPSIS
        Computes a deterministic digest for a grader record set.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Records
    )

    $canonical = @($Records | Sort-Object Source, Stimulus, Name | ForEach-Object {
            [ordered]@{
                evalName       = $_.EvalName
                source         = $_.Source
                stimulus       = $_.Stimulus
                graderType     = $_.GraderType
                resultKind     = $_.ResultKind
                name           = $_.Name
                behaviorSha256 = $_.BehaviorSha256
            }
        }) | ConvertTo-Json -Depth 20 -Compress
    return Get-LineageSha256 -Text $canonical
}

function New-GraderLineageMap {
    <#
    .SYNOPSIS
        Creates and validates the revision-bound lineage map object.
    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$SourceProvenanceRevision,

        [Parameter(Mandatory = $true)]
        [string]$SourceRevision,

        [Parameter(Mandatory = $true)]
        [string]$TargetRevision
    )

    Assert-GraderLineageRevisions @PSBoundParameters
    Import-LineageYamlModule

    $paths = @(Get-LineageMigrationPaths -RepoRoot $RepoRoot -SourceRevision $SourceRevision -TargetRevision $TargetRevision)
    $sourceRecords = @(Get-GraderLineageRecords -RepoRoot $RepoRoot -Revision $SourceRevision -Paths $paths)
    $targetRecords = @(Get-GraderLineageRecords -RepoRoot $RepoRoot -Revision $TargetRevision -Paths $paths)
    $pairs = @(Compare-GraderLineageRecords -SourceRecords $sourceRecords -TargetRecords $targetRecords)

    $aliases = [System.Collections.Generic.List[object]]::new()
    $generatedCopies = 0
    foreach ($pair in $pairs) {
        if ($pair.Source.Name -eq $pair.Target.Name) {
            continue
        }
        if ($pair.Source.Source -eq $script:GeneratedSpecPath) {
            $generatedCopies++
            continue
        }
        $aliases.Add([ordered]@{
                evalName       = $pair.Source.EvalName
                source         = $pair.Source.Source
                stimulus       = $pair.Source.Stimulus
                graderType     = $pair.Source.GraderType
                resultKind     = $pair.Source.ResultKind
                oldName        = $pair.Source.Name
                newName        = $pair.Target.Name
                behaviorSha256 = $pair.Source.BehaviorSha256
            })
    }
    $sortedAliases = @($aliases | Sort-Object evalName, source, stimulus, oldName)

    if ($pairs.Count -ne $script:ExpectedSourceToTargetPairs) {
        throw "Expected $($script:ExpectedSourceToTargetPairs) source-to-target pairs, found $($pairs.Count)."
    }
    if ($sortedAliases.Count -ne $script:ExpectedAuthoredAliases) {
        throw "Expected $($script:ExpectedAuthoredAliases) authored aliases, found $($sortedAliases.Count)."
    }
    if ($generatedCopies -ne $script:ExpectedGeneratedCopies) {
        throw "Expected $($script:ExpectedGeneratedCopies) generated copies, found $generatedCopies."
    }

    $oldKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $newKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($alias in $sortedAliases) {
        $oldKey = "$($alias.evalName)`n$($alias.stimulus)`n$($alias.resultKind)`n$($alias.oldName)"
        $newKey = "$($alias.evalName)`n$($alias.stimulus)`n$($alias.resultKind)`n$($alias.newName)"
        if (-not $oldKeys.Add($oldKey)) {
            throw "Duplicate historical composite key for '$($alias.oldName)'."
        }
        if (-not $newKeys.Add($newKey)) {
            throw "Duplicate current composite key for '$($alias.newName)'."
        }
    }

    $aliasJson = $sortedAliases | ConvertTo-Json -Depth 20 -Compress
    return [ordered]@{
        schemaVersion              = '1.0'
        migrationId               = 'vally-grader-names-v0.16'
        sourceProvenanceRevision   = $SourceProvenanceRevision
        sourceRevision             = $SourceRevision
        targetRevision             = $TargetRevision
        sourceSpecSha256           = Get-GraderRecordSetSha256 -Records $sourceRecords
        targetSpecSha256           = Get-GraderRecordSetSha256 -Records $targetRecords
        mapSha256                  = Get-LineageSha256 -Text $aliasJson
        counts                     = [ordered]@{
            sourceToTargetPairs = $pairs.Count
            authoredAliases     = $sortedAliases.Count
            generatedCopies     = $generatedCopies
            semanticChanges     = 0
        }
        aliases                    = $sortedAliases
    }
}

function Invoke-GraderLineageMap {
    <#
    .SYNOPSIS
        Builds or checks the committed lineage map.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $false)]
        [string]$SourceRevision,

        [Parameter(Mandatory = $false)]
        [string]$TargetRevision,

        [Parameter(Mandatory = $false)]
        [string]$SourceProvenanceRevision = 'ce4c686f8906288db28ccf8a1108c26e2ea52bd9',

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$Check
    )

    $resolvedRoot = Resolve-LineageRepoRoot -Override $RepoRoot
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $resolvedRoot 'evals/migrations/vally-0.16-grader-name-aliases.json'
    }

    if (([string]::IsNullOrWhiteSpace($SourceRevision) -or [string]::IsNullOrWhiteSpace($TargetRevision)) -and
        (Test-Path -LiteralPath $OutputPath)) {
        $existingMap = Get-Content -Raw -LiteralPath $OutputPath | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($SourceRevision)) {
            $SourceRevision = [string]$existingMap.sourceRevision
        }
        if ([string]::IsNullOrWhiteSpace($TargetRevision)) {
            $TargetRevision = [string]$existingMap.targetRevision
        }
        if ($PSBoundParameters.ContainsKey('SourceProvenanceRevision') -eq $false) {
            $SourceProvenanceRevision = [string]$existingMap.sourceProvenanceRevision
        }
    }

    if ([string]::IsNullOrWhiteSpace($SourceRevision) -or [string]::IsNullOrWhiteSpace($TargetRevision)) {
        throw 'SourceRevision and TargetRevision are required when no committed map is available.'
    }

    $map = New-GraderLineageMap -RepoRoot $resolvedRoot `
        -SourceProvenanceRevision $SourceProvenanceRevision `
        -SourceRevision $SourceRevision `
        -TargetRevision $TargetRevision
    $rendered = ($map | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
    $rendered += "`n"

    if ($Check) {
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            throw "Committed lineage map not found: $OutputPath"
        }
        $existing = [System.IO.File]::ReadAllText($OutputPath) -replace "`r`n", "`n"
        if ($existing -ne $rendered) {
            throw "Grader lineage map drift detected: $OutputPath"
        }
        Write-Host "grader lineage map is current: $OutputPath" -ForegroundColor Green
        return [pscustomobject]@{ Outcome = 'NoDrift'; OutputPath = $OutputPath; Counts = $map.counts }
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($OutputPath, 'Write grader lineage map')) {
        [System.IO.File]::WriteAllText($OutputPath, $rendered, [System.Text.UTF8Encoding]::new($false))
    }
    Write-Host "wrote grader lineage map: $OutputPath" -ForegroundColor Green
    return [pscustomobject]@{ Outcome = 'Wrote'; OutputPath = $OutputPath; Counts = $map.counts }
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-GraderLineageMap @PSBoundParameters
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Build-GraderLineageMap failed: $($_.Exception.Message)"
        exit 1
    }
}

#endregion Main Execution
