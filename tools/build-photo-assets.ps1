$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$thumbnailRoot = Join-Path $projectRoot 'img_thumbs'
$displayRoot = Join-Path $projectRoot 'img_display'
$manifestPath = Join-Path $projectRoot 'photo-manifest.js'

Add-Type -AssemblyName System.Drawing

function Get-OrientedImageDimensions {
    param([Parameter(Mandatory)][string]$Path)

    $image = [System.Drawing.Image]::FromFile($Path)
    try {
        $width = $image.Width
        $height = $image.Height
        $orientation = 1

        if ($image.PropertyIdList -contains 274) {
            $orientation = $image.GetPropertyItem(274).Value[0]
        }

        if ($orientation -in @(5, 6, 7, 8)) {
            $temporaryWidth = $width
            $width = $height
            $height = $temporaryWidth
        }

        return [PSCustomObject]@{ Width = $width; Height = $height }
    } finally {
        $image.Dispose()
    }
}

$categories = @(
    [PSCustomObject]@{ RelativeFolder = 'img new/events'; Label = 'Events'; Slug = 'events' }
    [PSCustomObject]@{ RelativeFolder = 'img new/hungary gp'; Label = 'Hungary GP'; Slug = 'hungary-gp' }
    [PSCustomObject]@{ RelativeFolder = 'img new/nature and water'; Label = 'Nature and Water'; Slug = 'nature-and-water' }
    [PSCustomObject]@{ RelativeFolder = 'img new/sky and from above'; Label = 'Sky and From Above'; Slug = 'sky-and-from-above' }
    [PSCustomObject]@{ RelativeFolder = 'img new/street and architecture'; Label = 'Street and Architecture'; Slug = 'street-and-architecture' }
    [PSCustomObject]@{ RelativeFolder = 'img faves'; Label = 'The Favorites'; Slug = 'the-favorites' }
)

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    throw 'ImageMagick (magick.exe) is required to build gallery thumbnails.'
}

New-Item -ItemType Directory -Force -Path $thumbnailRoot | Out-Null
New-Item -ItemType Directory -Force -Path $displayRoot | Out-Null
$manifest = @()

foreach ($category in $categories) {
    $sourceFolder = Join-Path $projectRoot $category.RelativeFolder
    $outputFolder = Join-Path $thumbnailRoot $category.Slug
    $displayFolder = Join-Path $displayRoot $category.Slug
    New-Item -ItemType Directory -Force -Path $outputFolder | Out-Null
    New-Item -ItemType Directory -Force -Path $displayFolder | Out-Null

    $photos = @()
    $allSourceFiles = @(Get-ChildItem -LiteralPath $sourceFolder -File |
        Where-Object { $_.Extension -match '^\.(jpe?g|png)$' } |
        Sort-Object Name)

    if ($category.Slug -eq 'the-favorites') {
        $firstFavorite = @($allSourceFiles | Where-Object { $_.Name -eq 'DSC_0524-Edit.jpg' })
        $secondFavorite = @($allSourceFiles | Where-Object { $_.Name -eq 'sharpen fo screen.jpg' })
        $otherFavorites = @($allSourceFiles |
            Where-Object { $_.Name -notin @('DSC_0524-Edit.jpg', 'sharpen fo screen.jpg') } |
            Sort-Object { Get-Random })
        $sourceFiles = @($firstFavorite) + @($secondFavorite) + @($otherFavorites)
    } else {
        $sourceFiles = $allSourceFiles
    }

    foreach ($sourceFile in $sourceFiles) {
        $safeStem = ($sourceFile.BaseName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
        $smallName = "$safeStem-640.webp"
        $largeName = "$safeStem-1280.webp"
        $displayName = "$safeStem-2560.webp"
        $smallPath = Join-Path $outputFolder $smallName
        $largePath = Join-Path $outputFolder $largeName
        $displayPath = Join-Path $displayFolder $displayName

        $smallNeedsBuild = -not (Test-Path -LiteralPath $smallPath) -or
            $sourceFile.LastWriteTimeUtc -gt (Get-Item -LiteralPath $smallPath -ErrorAction SilentlyContinue).LastWriteTimeUtc
        $largeNeedsBuild = -not (Test-Path -LiteralPath $largePath) -or
            $sourceFile.LastWriteTimeUtc -gt (Get-Item -LiteralPath $largePath -ErrorAction SilentlyContinue).LastWriteTimeUtc
        $displayNeedsBuild = -not (Test-Path -LiteralPath $displayPath) -or
            $sourceFile.LastWriteTimeUtc -gt (Get-Item -LiteralPath $displayPath -ErrorAction SilentlyContinue).LastWriteTimeUtc

        if ($smallNeedsBuild) {
            & magick $sourceFile.FullName -auto-orient -strip -resize '640x640>' -quality 84 $smallPath
            if ($LASTEXITCODE -ne 0) { throw "Failed to create $smallPath" }
        }

        if ($largeNeedsBuild) {
            & magick $sourceFile.FullName -auto-orient -strip -resize '1280x1280>' -quality 88 $largePath
            if ($LASTEXITCODE -ne 0) { throw "Failed to create $largePath" }
        }

        if ($displayNeedsBuild) {
            & magick $sourceFile.FullName -auto-orient -strip -resize '2560x2560>' -define 'webp:method=4' -quality 90 $displayPath
            if ($LASTEXITCODE -ne 0) { throw "Failed to create $displayPath" }
        }

        $relativeOriginal = 'img_display/{0}/{1}' -f $category.Slug, $displayName
        $relativeSmall = 'img_thumbs/{0}/{1}' -f $category.Slug, $smallName
        $relativeLarge = 'img_thumbs/{0}/{1}' -f $category.Slug, $largeName
        $dimensions = Get-OrientedImageDimensions -Path $sourceFile.FullName

        $photos += [PSCustomObject]@{
            original = $relativeOriginal
            small = $relativeSmall
            large = $relativeLarge
            alt = '{0} photograph {1}' -f $category.Label, $sourceFile.BaseName
            width = $dimensions.Width
            height = $dimensions.Height
        }
    }

    $manifest += [PSCustomObject]@{
        id = $category.Slug
        label = $category.Label
        photos = $photos
    }
}

$json = $manifest | ConvertTo-Json -Depth 5 -Compress
$javascript = "window.PHOTO_CATEGORIES = $json;`n"
[System.IO.File]::WriteAllText($manifestPath, $javascript, [System.Text.UTF8Encoding]::new($false))

$photoCount = ($manifest | ForEach-Object { $_.photos.Count } | Measure-Object -Sum).Sum
Write-Host "Built $($manifest.Count) categories containing $photoCount photos."
