function Prompt {
    $currentPath = $executionContext.SessionState.Path.CurrentLocation.Path
    $currentDirectory = $currentPath -replace '.*\\([^\\]+)', '$1'

    $durationInfo = if ($he = Get-History -Count 1) {
        '({0:N2}s) ' -f ($he.EndExecutionTime - $he.StartExecutionTime).TotalSeconds
    }

    $blue = $PSStyle.Foreground.Blue
    $bold = $PSStyle.Bold
    $reset = $PSStyle.Reset

    return "$blue$bold$currentDirectory$reset $bold$durationInfo"
}

Set-Alias -Name lg -Value lazygit