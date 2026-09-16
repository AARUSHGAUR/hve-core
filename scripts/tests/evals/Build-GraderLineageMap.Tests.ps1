#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts/evals/Build-GraderLineageMap.ps1'
    $script:SourceRevision = 'b4c940cc4067d9b2addbba48ea15e599f4c825c4'
    $script:TargetRevision = '0b8762fe0003396557820bd6093d88a932047033'
    $script:ProvenanceRevision = 'ce4c686f8906288db28ccf8a1108c26e2ea52bd9'

    Import-Module powershell-yaml -ErrorAction Stop
    . $script:ScriptPath
}

Describe 'Build-GraderLineageMap.ps1' -Tag 'Unit' {
    It 'Generates the deterministic revision-bound migration contract' {
        $first = New-GraderLineageMap -RepoRoot $script:RepoRoot `
            -SourceProvenanceRevision $script:ProvenanceRevision `
            -SourceRevision $script:SourceRevision `
            -TargetRevision $script:TargetRevision
        $second = New-GraderLineageMap -RepoRoot $script:RepoRoot `
            -SourceProvenanceRevision $script:ProvenanceRevision `
            -SourceRevision $script:SourceRevision `
            -TargetRevision $script:TargetRevision

        $first.counts.sourceToTargetPairs | Should -Be 1240
        $first.counts.authoredAliases | Should -Be 414
        $first.counts.generatedCopies | Should -Be 171
        $first.counts.semanticChanges | Should -Be 0
        $first.aliases | Should -HaveCount 414
        $first.mapSha256 | Should -BeExactly $second.mapSha256
        $first.sourceRevision | Should -BeExactly $script:SourceRevision
        $first.targetRevision | Should -BeExactly $script:TargetRevision
        $first.sourceSpecSha256 | Should -Match '^[a-f0-9]{64}$'
        $first.targetSpecSha256 | Should -Match '^[a-f0-9]{64}$'
    }

    It 'Maps authored grader type <GraderType> to result kind <ExpectedKind>' -ForEach @(
        @{ GraderType = 'output-matches'; ExpectedKind = 'code' }
        @{ GraderType = 'output-contains'; ExpectedKind = 'code' }
        @{ GraderType = 'wall-time'; ExpectedKind = 'code' }
        @{ GraderType = 'prompt'; ExpectedKind = 'llm' }
        @{ GraderType = 'human'; ExpectedKind = 'human' }
    ) {
        Get-GraderResultKind -GraderType $GraderType | Should -BeExactly $ExpectedKind
    }

    It 'Rejects ambiguous and semantic source-to-target pairs' {
        $record = [pscustomobject]@{
            PairKey = 'source|stimulus|digest'
            GraderType = 'output-matches'
            ResultKind = 'code'
            Name = 'old-name'
        }
        $target = [pscustomobject]@{
            PairKey = 'source|stimulus|digest'
            GraderType = 'output-matches'
            ResultKind = 'code'
            Name = 'new-name'
        }
        $semanticChange = [pscustomobject]@{
            PairKey = 'source|stimulus|other-digest'
            GraderType = 'output-matches'
            ResultKind = 'code'
            Name = 'new-name'
        }

        { Compare-GraderLineageRecords -SourceRecords @($record, $record) -TargetRecords @($target, $target) } |
            Should -Throw -ExpectedMessage '*Ambiguous source grader pair*'
        { Compare-GraderLineageRecords -SourceRecords @($record) -TargetRecords @($semanticChange) } |
            Should -Throw -ExpectedMessage '*Semantic grader change*'
    }

    It 'Rejects unreachable revisions and provenance drift' {
        {
            Assert-GraderLineageRevisions -RepoRoot $script:RepoRoot `
                -SourceProvenanceRevision $script:ProvenanceRevision `
                -SourceRevision ('0' * 40) `
                -TargetRevision $script:TargetRevision
        } | Should -Throw -ExpectedMessage '*Git command failed*'

        {
            Assert-GraderLineageRevisions -RepoRoot $script:RepoRoot `
                -SourceProvenanceRevision $script:TargetRevision `
                -SourceRevision $script:SourceRevision `
                -TargetRevision $script:TargetRevision
        } | Should -Throw -ExpectedMessage '*does not match provenance*'
    }
}
