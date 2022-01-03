gcemuhook_sources = [
  'AbstractPhysicalDevice.vala',
  'Constants.vala',
  'Server.vala',
  'Utils.vala',
  'WrapperPhysicalDevice.vala'
]

gcemuhook_deps = [
  dependency('glib-2.0', version: '>= 2.50'),
  dependency('gio-2.0',  version: '>= 2.50'),
  dependency('gee-0.8',  version: '>= 0.20'),
  dependency('zlib',     version: '>= 1.2'),
]

gcemuhook = library ('gcemuhook-0.1', gcemuhook_sources,
  dependencies: gcemuhook_deps,
  vala_header: 'gcemuhook-0.1.h',
  vala_vapi: 'gcemuhook-0.1.vapi',
  vala_gir: 'gcemuhook-0.1.gir',
  install: true,
  install_dir: [true, true, true, true],

  vala_args: '--enable-experimental-non-null'
)

install_data('gcemuhook-0.1.deps', install_dir : get_option('datadir') / 'vala' / 'vapi')

pkg = import('pkgconfig')
pkg.generate(gcemuhook,
  description: 'Cemuhook protocol helper',
  requires: [dependency('gobject-2.0',  version: '>= 2.50')]
)

# TODO: make optional
g_ir_compiler = find_program('g-ir-compiler')

custom_target('gcemuhook typelib', command: [g_ir_compiler, '--output', '@OUTPUT@', join_paths(meson.current_build_dir(), 'gcemuhook-0.1.gir')],
              output: 'gcemuhook-0.1.typelib',
              depends: gcemuhook,
              install: true,
              install_dir: get_option('libdir') / 'girepository-1.0')
