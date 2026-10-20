$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\HuNaoAutoDL.Windows\HuNaoAutoDL.Windows.csproj'))
$dist = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'dist\windows'
Write-Host "Restoring Windows dependencies..."
dotnet restore $project
Write-Host "Publishing self-contained win-x64 build..."
dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o $dist
Write-Host "完成：$dist\HuNaoAutoDL.Windows.exe"
