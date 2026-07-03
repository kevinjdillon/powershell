param($Path, [switch]$Remove)
if ($Remove) {
    Get-ChildItem $Path -File -Recurse -Filter "*.txt" | Rename-Item -NewName {$_.Name -replace '\.txt$',''}
} else {
    Get-ChildItem $Path -File -Recurse | Rename-Item -NewName {$_.Name + ".txt"}
}
