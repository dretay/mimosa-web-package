"use strict"


exports.writeSpecFile = (config, logger, tmpDir, buildRoot)->
  fs = require 'fs'
  wrench = require('wrench')
  path = require 'path'
  _ = require 'underscore'

  buildRootIndex = config.webPackage.outPath.indexOf("BUILDROOT")
  tmpDir = path.resolve(config.webPackage.outPath.substr(0,buildRootIndex));

  pkgName = config.webPackage.easyRpm.name + "-" + config.webPackage.easyRpm.version + "-" + config.webPackage.easyRpm.buildArch
  specFilepath = path.join(tmpDir, "SPECS", pkgName + ".spec")
  buffer = []
  files = _.filter (wrench.readdirSyncRecursive buildRoot), (file)->
    file = buildRoot+"/"+file
    unless fs.lstatSync(file).isDirectory() then return true
    logger.debug "Excluding #{file} from RPM because its a directory"
    return false



  buffer.push("%define   _topdir " + tmpDir)
  buffer.push("");
  buffer.push("Name: "+config.webPackage.easyRpm.name)
  buffer.push("Version: "+config.webPackage.easyRpm.version)
  buffer.push("Release: "+config.webPackage.easyRpm.release)
  buffer.push("Group: "+config.webPackage.easyRpm.group)
  buffer.push("Summary: "+config.webPackage.easyRpm.summary)
  buffer.push("Group: "+config.webPackage.easyRpm.group)
  buffer.push("License: "+config.webPackage.easyRpm.license)
  buffer.push("BuildArch: "+config.webPackage.easyRpm.buildArch)
  if typeof config.webPackage.easyRpm.autoReqProv != "undefined" then buffer.push("AutoReqProv: "+config.webPackage.easyRpm.autoReqProv)

  if config.webPackage.easyRpm.dependencies.length > 0 then buffer.push("Requires: " + config.webPackage.easyRpm.dependencies.join(","))

  buffer.push("")
  buffer.push("%description")
  buffer.push(config.webPackage.easyRpm.description)
  buffer.push("")
  buffer.push("%files")
  buffer.push("%defattr(-, root, root, -)")
  for file in files
    if file.indexOf('%') == 0
      buffer.push(files[i])
    else
      buffer.push("\"/"+file+"\"")

  buffer.push("")
  buffer.push("%pre")
  buffer.push(preInstallScript) for preInstallScript in config.webPackage.easyRpm.preInstallScript


  buffer.push("")
  buffer.push("%post")
  buffer.push(postInstallScript) for postInstallScript in config.webPackage.easyRpm.postInstallScript


  buffer.push("")
  buffer.push("%preun")
  buffer.push(preUninstallScript) for preUninstallScript in config.webPackage.easyRpm.preUninstallScript


  buffer.push("")
  buffer.push("%postun")
  buffer.push(postUninstallScript) for postUninstallScript in config.webPackage.easyRpm.postUninstallScript

  specFileContent = buffer.join("\n")
  fs.writeFileSync specFilepath, specFileContent
  return specFilepath
