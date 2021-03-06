assert = require 'assert'
Path   = require 'path'
fs     = require 'fs'
R      = require 'reactive'
scopedfs = require 'scopedfs'
{RelPathList} = require 'pathspec'
JobQueue = require 'jobqueue'

{ ok, equal, deepEqual } = require 'assert'

{ EventEmitter } = require 'events'

{ Session, R, Project } = require "../#{process.env.JSLIB or 'lib'}/session"
TestVFS = require 'vfs-test'

DataDir = Path.join(__dirname, 'data')

readMementoSync = (name) -> JSON.parse(fs.readFileSync(Path.join(DataDir, name), 'utf8'))

class FakeSession
  constructor: ->
    @plugins = []
    @queue = new JobQueue()

    @pluginManager =
      allCompilers: []

  after: (func, description) ->
    @queue.after (=> process.nextTick func), description

  findCompilerById: (compilerId) ->
    { id: compilerId }


describe "Project", ->

  it "should report basic info about itself", (done) ->
    vfs = new TestVFS()
    session = new FakeSession()

    universe = new R.Universe()
    project = universe.create(Project, { session, vfs, path: "/foo/bar" })
    assert.equal project.name, 'bar'
    assert.equal project.path, '/foo/bar'
    assert.ok project.id.match /^P\d+_bar$/
    project.once 'complete', done


  it "should be able to load an empty memento", (done) ->
    vfs = new TestVFS()
    session = new FakeSession()

    universe = new R.Universe()
    project = universe.create(Project, { session, vfs, path: "/foo/bar" })
    project.setMemento {}

    project.once 'complete', done


  it "should be able to load a simple memento", (done) ->
    vfs = new TestVFS()

    session = new FakeSession()

    universe = new R.Universe()
    project = universe.create(Project, { session, vfs, path: "/foo/bar" })
    project.setMemento { disableLiveRefresh: 1, compilationEnabled: 1 }

    project.once 'complete', done


  it "should be able to load a real memento", (done) ->
    vfs = new TestVFS()

    session = new FakeSession()

    universe = new R.Universe()
    project = universe.create(Project, { session, vfs, path: "/foo/bar" })
    project.setMemento readMementoSync('project_memento.json')

    assert.equal project.compilationEnabled, true
    assert.equal project.rubyVersionId, 'system'

    project.once 'complete', done


  it "should save CSS files edited in Chrome Web Inspector", (done) ->
    vfs = new TestVFS()
    vfs.put '/foo/bar/app/static/test.css', "h1 { color: red }\n"

    session = new FakeSession()

    universe = new R.Universe()
    project = universe.create(Project, { session, vfs, path: "/foo/bar" })
    await project.saveResourceFromWebInspector 'http://example.com/static/test.css', "h1 { color: green }\n", defer(err, saved)
    assert.ifError err
    assert.ok saved
    assert.equal vfs.get('/foo/bar/app/static/test.css'), "h1 { color: green }\n"

    project.once 'complete', done


  it "should patch source SCSS/Stylus files when a compiled CSS is edited in Chrome Web Inspector", (done) ->
    styl1 = "h1\n  color red\n\nh2\n  color blue\n\nh3\n  color yellow\n"
    styl2 = styl1.replace 'blue', 'black'
    css1  = "/* line 1 : test.styl */\nh1 { color: red }\n/* line 4 : test.styl */\nh2 { color: blue }\n/* line 7 : test.styl */\nh3 { color: yellow }\n"
    css2  = css1.replace 'blue', 'black'

    vfs = new TestVFS()
    vfs.put '/foo/bar/app/static/test.styl', styl1
    vfs.put '/foo/bar/app/static/test.css', css1

    session = new FakeSession()

    universe = new R.Universe()
    project = universe.create(Project, { session, vfs, path: "/foo/bar" })
    await project.saveResourceFromWebInspector 'http://example.com/static/test.css', css2, defer(err, saved)
    assert.ifError err
    assert.ok saved
    assert.equal vfs.get('/foo/bar/app/static/test.css'), css2
    assert.equal vfs.get('/foo/bar/app/static/test.styl'), styl2

    project.once 'complete', done


  it "should be reactive", (done) ->
    universe = new R.Universe()
    vfs = new TestVFS()

    session = new FakeSession()

    project = universe.create(Project, { session, vfs, path: "/foo/bar" })

    await
      project.once 'complete', defer()
      universe.once 'change', defer()
      project.setMemento { disableLiveRefresh: 1, compilationEnabled: 1 }

    done()


  describe "plugin support", ->

    it "should run plugin.loadProject on setMemento", (done) ->
      vfs = new TestVFS()

      session = new FakeSession()
      session.plugins.push
        loadProject: (project, memento) ->
          project.foo = memento.bar

      universe = new R.Universe()
      project = universe.create(Project, { session, vfs, path: "/foo/bar" })
      project.setMemento { disableLiveRefresh: 1, bar: 42 }

      assert.equal project.foo, 42

      project.once 'complete', done


  describe "rule system", ->

    class TestContext
      constructor: ->

    it.skip "should start new projects with a full set of supported rules", (done) ->
      universe = new R.Universe()
      vfs = new TestVFS()
      session = new FakeSession()
      # TODO: add some kind of fuzzy dependency injection to collapse these stupid chains
      session.pluginManager.allCompilers.push {
        name:            'LESS'
        id:              'less'
        extensions:      ['less']
        destinationExt:  'css'
        sourceSpecs:     ["*.less"]
        sourceFilter:    RelPathList.parse("*.less")
      }
      session.pluginManager.allCompilers.push {
        name:            'CoffeeScript'
        id:              'coffeescript'
        extensions:      ['coffee']
        destinationExt:  'js'
        sourceSpecs:     ["*.coffee"]
        sourceFilter:    RelPathList.parse("*.less")
        sourceFilter:    RelPathList.parse("*.coffee")
      }

      project = universe.create(Project, { session, vfs, path: "/foo/bar" })
      project.setMemento {}
      await project.once 'complete', defer()
      deepEqual project.ruleSet.memento(), [{ action: 'compile-less', src: '**/*.less', dst: '**/*.css' }, { action: 'compile-coffeescript', src: '**/*.coffee', dst: '**/*.js' }]
      done()

    it.skip "should resolve the list of files matched by each rule", (done) ->
      universe = new R.Universe()
      vfs = new TestVFS()
      session = new FakeSession()
      # TODO: add some kind of fuzzy dependency injection to collapse these stupid chains
      session.pluginManager.allCompilers.push {
        name:            'LESS'
        id:              'less'
        extensions:      ['less']
        destinationExt:  'css'
        sourceSpecs:     ["*.less"]
        sourceFilter:    RelPathList.parse("*.less")
      }
      session.pluginManager.allCompilers.push {
        name:            'CoffeeScript'
        id:              'coffeescript'
        extensions:      ['coffee']
        destinationExt:  'js'
        sourceSpecs:     ["*.coffee"]
        sourceFilter:    RelPathList.parse("*.coffee")
      }

      tempfs = scopedfs.createTempFS('livereload-test-')
      tempfs.applySync
        'foo.less':   "h1 { span { color: red } }\n"
        'bar.coffee': "alert 42\n"

      project = universe.create(Project, { session, vfs, path: tempfs.path })
      project.setMemento {}
      await project.once 'complete', defer()

      equal project.ruleSet.rules[0].action.id, 'compile-less'
      deepEqual (f.relpath for f in project.ruleSet.rules[0].files).sort(), ['foo.less']

      equal project.ruleSet.rules[1].action.id, 'compile-coffeescript'
      deepEqual (f.relpath for f in project.ruleSet.rules[1].files).sort(), ['bar.coffee']
      done()

    it "should use rules to determine compiler and output path"
    it "should allow rules to be modified in the UI"
