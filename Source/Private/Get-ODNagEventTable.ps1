function Get-ODNagEventTable {
    <#
    .SYNOPSIS
        Returns every event the module can log, keyed by event name (which is also its stage).
    .DESCRIPTION
        The one place events are defined. Each entry has EventId, Stage and EntryType. A new event
        goes here and in the README event table. TimedOut and Dismissed are distinct stages that
        share one ID per prompt kind.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $table = @{}
    $define = {
        param($Name, $Id, $Type = 'Information')
        $table[$Name] = @{ EventId = $Id; Stage = $Name; EntryType = $Type }
    }

    foreach ($kind in @(
            @{ Name = 'FirstLogin'; Ids = 1000, 1001, 1002, 1004 }
            @{ Name = 'Reauth'; Ids = 1005, 1006, 1007, 1008 }
        )) {
        & $define "$($kind.Name)Shown" $kind.Ids[0]
        & $define "$($kind.Name)Acted" $kind.Ids[1]
        & $define "$($kind.Name)Deferred" $kind.Ids[2] 'Warning'
        & $define "$($kind.Name)TimedOut" $kind.Ids[3] 'Warning'
        & $define "$($kind.Name)Dismissed" $kind.Ids[3] 'Warning'
        & $define "$($kind.Name)SignedInElsewhere" 1014
    }
    & $define 'Healthy' 1003
    & $define 'StatusUnknown' 1010
    & $define 'Degraded' 1011 'Warning'
    & $define 'EmailLookupFailed' 1012 'Warning'
    & $define 'ClientNotFound' 1013 'Error'

    $table
}
