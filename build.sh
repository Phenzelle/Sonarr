#! /bin/bash
msBuild='/c/Program Files (x86)/MSBuild/14.0/Bin'
outputFolder='./_output'
outputFolderLinux='./_output_linux'
outputFolderMacOS='./_output_macos'
outputFolderMacOSApp='./_output_macos_app'
testPackageFolder='./_tests/'
testSearchPattern='*.Test/bin/x86/Release'
sourceFolder='./src'
slnFile=$sourceFolder/Sonarr.sln
updateFolder=$outputFolder/Sonarr.Update
updateFolderMono=$outputFolderLinux/Sonarr.Update

nuget='tools/nuget/nuget.exe';
CheckExitCode()
{
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "error with $1" >&2
        exit 1
    fi
    return $status
}

ProgressStart()
{
    echo "##teamcity[blockOpened name='$1']"
    echo "##teamcity[progressStart '$1']"
}

ProgressEnd()
{
    echo "##teamcity[progressFinish '$1']"
    echo "##teamcity[blockClosed name='$1']"
}

CleanFolder()
{
    local path=$1
    local keepConfigFiles=$2

    find $path -name "*.transform" -exec rm "{}" \;

    if [ $keepConfigFiles != true ] ; then
        find $path -name "*.dll.config" -exec rm "{}" \;
    fi

    echo "Removing FluentValidation.Resources files"
    find $path -name "FluentValidation.resources.dll" -exec rm "{}" \;
    find $path -name "App.config" -exec rm "{}" \;

    echo "Removing vshost files"
    find $path -name "*.vshost.exe" -exec rm "{}" \;

    echo "Removing dylib files"
    find $path -name "*.dylib" -exec rm "{}" \;

    echo "Removing Empty folders"
    find $path -depth -empty -type d -exec rm -r "{}" \;
}

AddJsonNet()
{
    rm $outputFolder/Newtonsoft.Json.*
    cp $sourceFolder/packages/Newtonsoft.Json.*/lib/net35/*.dll $outputFolder
    cp $sourceFolder/packages/Newtonsoft.Json.*/lib/net35/*.dll $updateFolder
}

BuildWithMSBuild()
{
    export PATH=$msBuild:$PATH
    CheckExitCode MSBuild.exe $slnFile //t:Clean //m
    $nuget restore $slnFile
    CheckExitCode MSBuild.exe $slnFile //p:Configuration=Release //p:Platform=x86 //t:Build //m //p:AllowedReferenceRelatedFileExtensions=.pdb
}

BuildWithXbuild()
{
    export MONO_IOMAP=case
    CheckExitCode xbuild /t:Clean $slnFile
    mono $nuget restore $slnFile
    CheckExitCode xbuild /p:Configuration=Release /p:Platform=x86 /t:Build /p:AllowedReferenceRelatedFileExtensions=.pdb $slnFile
}

LintUI()
{
    ProgressStart 'ESLint'
    CheckExitCode yarn eslint
    ProgressEnd 'ESLint'

    ProgressStart 'Stylelint'
    CheckExitCode yarn stylelint
    ProgressEnd 'Stylelint'
}

Build()
{
    ProgressStart 'Build'

    rm -rf $outputFolder

    if [ $runtime = "dotnet" ] ; then
        BuildWithMSBuild
    else
        BuildWithXbuild
    fi

    CleanFolder $outputFolder false

    AddJsonNet

    echo "Removing Mono.Posix.dll"
    rm $outputFolder/Mono.Posix.dll

    ProgressEnd 'Build'
}

RunGulp()
{
    ProgressStart 'yarn install'
    yarn install
    ProgressEnd 'yarn install'

    LintUI

    ProgressStart 'Running gulp'
    CheckExitCode yarn run build --production
    ProgressEnd 'Running gulp'
}

CreateMdbs()
{
    local path=$1
    if [ $runtime = "dotnet" ] ; then
        local pdbFiles=( $(find $path -name "*.pdb") )
        for filename in "${pdbFiles[@]}"
        do
          if [ -e ${filename%.pdb}.dll ]  ; then
            tools/pdb2mdb/pdb2mdb.exe ${filename%.pdb}.dll
          fi
          if [ -e ${filename%.pdb}.exe ]  ; then
            tools/pdb2mdb/pdb2mdb.exe ${filename%.pdb}.exe
          fi
        done
    fi
}

PackageMono()
{
    ProgressStart 'Creating Mono Package'

    rm -rf $outputFolderLinux
    cp -r $outputFolder $outputFolderLinux

    echo "Creating MDBs"
    CreateMdbs $outputFolderLinux

    echo "Removing PDBs"
    find $outputFolderLinux -name "*.pdb" -exec rm "{}" \;

    echo "Removing Service helpers"
    rm -f $outputFolderLinux/ServiceUninstall.*
    rm -f $outputFolderLinux/ServiceInstall.*

    echo "Removing native windows binaries Sqlite, MediaInfo"
    rm -f $outputFolderLinux/sqlite3.*
    rm -f $outputFolderLinux/MediaInfo.*

    echo "Adding Sonarr.Core.dll.config (for dllmap)"
    cp $sourceFolder/NzbDrone.Core/Sonarr.Core.dll.config $outputFolderLinux

    echo "Adding CurlSharp.dll.config (for dllmap)"
    cp $sourceFolder/NzbDrone.Common/CurlSharp.dll.config $outputFolderLinux

    echo "Renaming Sonarr.Console.exe to Sonarr.exe"
    rm $outputFolderLinux/Sonarr.exe*
    for file in $outputFolderLinux/Sonarr.Console.exe*; do
        mv "$file" "${file//.Console/}"
    done

    echo "Removing Sonarr.Windows"
    rm $outputFolderLinux/Sonarr.Windows.*

    echo "Adding Sonarr.Mono to UpdatePackage"
    cp $outputFolderLinux/Sonarr.Mono.* $updateFolderMono

    ProgressEnd 'Creating Mono Package'
}

PackageOsx()
{
    ProgressStart 'Creating MacOS Package'

    rm -rf $outputFolderMacOS
    cp -r $outputFolderLinux $outputFolderMacOS

    echo "Adding sqlite dylibs"
    cp $sourceFolder/Libraries/Sqlite/*.dylib $outputFolderMacOS

    echo "Adding MediaInfo dylib"
    cp $sourceFolder/Libraries/MediaInfo/*.dylib $outputFolderMacOS

    echo "Adding Startup script"
    cp  ./osx/Sonarr $outputFolderMacOS

    ProgressEnd 'Creating MacOS Package'
}

PackageOsxApp()
{
    ProgressStart 'Creating MacOS App Package'

    rm -rf $outputFolderMacOSApp
    mkdir $outputFolderMacOSApp

    cp -r ./osx/Sonarr.app $outputFolderMacOSApp
    cp -r $outputFolderMacOS $outputFolderMacOSApp/Sonarr.app/Contents/MacOS

    ProgressEnd 'Creating MacOS App Package'
}

PackageTests()
{
    ProgressStart 'Creating Test Package'

    rm -rf $testPackageFolder
    mkdir $testPackageFolder

    find $sourceFolder -path $testSearchPattern -exec cp -r -u -T "{}" $testPackageFolder \;

    if [ $runtime = "dotnet" ] ; then
        $nuget install NUnit.ConsoleRunner -Version 3.2.0 -Output $testPackageFolder
    else
        mono $nuget install NUnit.ConsoleRunner -Version 3.2.0 -Output $testPackageFolder
    fi

    cp $outputFolder/*.dll $testPackageFolder
    cp ./test.sh $testPackageFolder

    echo "Creating MDBs for tests"
    CreateMdbs $testPackageFolder

    rm -f $testPackageFolder/*.log.config

    CleanFolder $testPackageFolder true

    echo "Adding Sonarr.Core.dll.config (for dllmap)"
    cp $sourceFolder/NzbDrone.Core/Sonarr.Core.dll.config $testPackageFolder

    echo "Adding CurlSharp.dll.config (for dllmap)"
    cp $sourceFolder/NzbDrone.Common/CurlSharp.dll.config $testPackageFolder

    echo "Copying CurlSharp libraries"
    cp $sourceFolder/ExternalModules/CurlSharp/libs/i386/* $testPackageFolder

    ProgressEnd 'Creating Test Package'
}

CleanupWindowsPackage()
{
    ProgressStart 'Cleaning Windows Package'

    echo "Removing Sonarr.Mono"
    rm -f $outputFolder/Sonarr.Mono.*

    echo "Adding Sonarr.Windows to UpdatePackage"
    cp $outputFolder/Sonarr.Windows.* $updateFolder

    ProgressEnd 'Cleaning Windows Package'
}

PublishArtifacts()
{
    ProgressStart 'Publishing Artifacts'

    # Tests
    echo "##teamcity[publishArtifacts '_tests/** => tests.zip']"

    # Releases
    echo "##teamcity[publishArtifacts '$outputFolder/** => Sonarr.$BRANCH.$BUILD_NUMBER.windows.zip!Sonarr']"
    echo "##teamcity[publishArtifacts '$outputFolderLinux/** => Sonarr.$BRANCH.$BUILD_NUMBER.linux.tar.gz!Sonarr']"
    echo "##teamcity[publishArtifacts '$outputFolderMacOS/** => Sonarr.$BRANCH.$BUILD_NUMBER.macos.tar.gz!Sonarr']"
    echo "##teamcity[publishArtifacts '$outputFolderMacOSApp/** => Sonarr.$BRANCH.$BUILD_NUMBER.macos.zip!Sonarr']"
    
    # Debian Package
    echo "##teamcity[publishArtifacts 'distribution/** => distribution.zip']"
    
    ProgressEnd 'Publishing Artifacts'
}

# Use mono or .net depending on OS
case "$(uname -s)" in
    CYGWIN*|MINGW32*|MINGW64*|MSYS*)
        # on windows, use dotnet
        runtime="dotnet"
        ;;
    *)
        # otherwise use mono
        runtime="mono"
        ;;
esac

Build
RunGulp
PackageMono
PackageOsx
PackageOsxApp
PackageTests
CleanupWindowsPackage
PublishArtifacts
