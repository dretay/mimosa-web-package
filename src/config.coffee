"use strict"

path = require 'path'

exports.defaults = ->
  webPackage:
    easyRpm:
      name: "noname",
      summary: "No Summary",
      description: "No Description",
      version: "0.1.0",
      release: "1",
      license: "MIT",
      vendor: "Vendor",
      group: "Development/Tools",
      buildArch: "noarch",
      dependencies: [],
      preInstallScript: [],
      postInstallScript: [],
      preUninstallScript: [],
      postUninstallScript: [],
      keepTemp: false
      targetDestination: "/"


    archiveName: "app"
    outPath: "dist"
    configName: "config"
    useEntireConfig: false
    exclude: ["README.md","node_modules","mimosa-config.coffee","mimosa-config-documented.coffee", "mimosa-config.js","assets",".git",".gitignore",".travis.yml", ".mimosa","bower.json"]
    appjs:"app.js"

exports.placeholder = ->
  """
  \t

    ###
    The webPackage module works hand in hand with the mimosa-server module to package web
    applications
    ###
    webPackage:                 # Configration for packaging of web applications
      archiveName: "app"        # a string, the name of the output .tar.gz/.zip file. No
                                # archive will be created if archiveName is set to null.
                                # A .zip will only be created if the archiveName ends in
                                # .zip.  Otherwise a tar file is assumed.  If the default is
                                # changed away from app, web-package will use the changed config
                                # setting.  If the default is left alone (only .tar),
                                # web-package will check the for a name property in the
                                # package.json, and if it exists, it will be used. If the default
                                # is left as app, and there is no package.json.name property,
                                # the default is used.
      outPath:"dist"            # Output path for assets to package, should be relative to the
                                # root of the project (location of mimosa-config) or be absolute
      configName:"config"       # the name of the config file, will be placed in outPath and have
                                # a .json extension. it is also acceptable to define a subdirectory
      useEntireConfig: false    # this module pulls out specific pieces of the mimosa-config that
                                # apply to  what you may need with a packaged application. For
                                # instance, it does not include a coffeescript config, or a jshint
                                # config. If you want it to include the entire resolved mimosa-config
                                # flip this flag to true.
      ###
      Exclude is a list of files/folders relative to the root of the app to not copy to the outPath
      as part of a package.  By default the watch.sourceDir is added to this list during processing.
      ###
      exclude:["README.md","node_modules","mimosa-config.coffee","mimosa-config-documented.coffee", "mimosa-config.js","assets",".git",".gitignore",".travis.yml",".mimosa","bower.json"]
      appjs: "app.js"           # name of the output app.js file which bootstraps the application,
                                # when set to null, web-package will not output a bootstrap file

  """

exports.validate = (config, validators) ->
  errors = []
  if validators.ifExistsIsObject(errors, "webPackage config", config.webPackage)

    if config.webPackage.outPath?
      if typeof config.webPackage.outPath is "string"
        config.webPackage.outPath = validators.determinePath config.webPackage.outPath, config.root

        #if we're building an RPM build out the appropriate install path
        if /\.rpm$/.test(config.webPackage.archiveName)
          unless /\/$/.test config.webPackage.easyRpm.installDestination
            config.webPackage.easyRpm.targetDestination += "/"
          unless /^\//.test config.webPackage.easyRpm.installDestination
            config.webPackage.easyRpm.installDestination = "/"+ config.webPackage.easyRpm.installDestination
          config.webPackage.outPath = config.webPackage.outPath+"/BUILDROOT#{config.webPackage.easyRpm.installDestination}"
      else
        errors.push "webPackage.outPath must be a string."

    validators.ifExistsIsString(errors, "webPackage.configName", config.webPackage.configName)
    validators.ifExistsIsString(errors, "webPackage.archiveName", config.webPackage.archiveName)

    validators.ifExistsIsBoolean(errors, "webPackage.useEntireConfig", config.webPackage.useEntireConfig)

    if validators.ifExistsIsArray(errors, "webPackage.exclude", config.webPackage.exclude)
      fullPathExcludes = []
      for ex in config.webPackage.exclude
        if typeof ex is "string"
          fullPathExcludes.push path.join config.root, ex
        else
          errors.push "webPackage.exclude must be an array of strings"
          break
      config.webPackage.exclude = fullPathExcludes
      if /\.rpm$/.test(config.webPackage.archiveName)
        buildRootIndex = config.webPackage.outPath.indexOf("BUILDROOT")
        tmpDir = path.resolve(config.webPackage.outPath.substr(0,buildRootIndex));
        config.webPackage.exclude.push tmpDir
      else
        config.webPackage.exclude.push config.webPackage.outPath

    validators.ifExistsIsString(errors, "webPackage.appjs", config.webPackage.appjs)

    if not config.server or not config.server.path
      config.webPackage.appjs = undefined



  errors
