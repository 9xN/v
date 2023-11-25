module main

import os
import flag
import strings

const tool_version = '0.0.4'
const tool_description = 'Converts a list of arbitrary files into a single v module file.'

struct Context {
mut:
	files       []string
	prefix      string
	show_help   bool
	module_name string
	write_file  string
}

fn (context Context) header() string {
	mut header_s := ''
	header_s += 'module ${context.module_name}\n'
	header_s += '\n'
	allfiles := context.files.join(' ')
	mut options := []string{}
	if context.prefix.len > 0 {
		options << '-p ${context.prefix}'
	}
	if context.module_name.len > 0 {
		options << '-m ${context.module_name}'
	}
	if context.write_file.len > 0 {
		options << '-w ${context.write_file}'
	}
	soptions := options.join(' ')
	header_s += '// File generated by:\n'
	header_s += '// v bin2v ${allfiles} ${soptions}\n'
	header_s += '// Please, do not edit this file.\n'
	header_s += '// Your changes may be overwritten.\n'
	header_s += 'const (\n'
	return header_s
}

fn (context Context) footer() string {
	return ')\n'
}

fn (context Context) file2v(bname string, fbytes []u8, bn_max int) string {
	mut sb := strings.new_builder(1000)
	bn_diff_len := bn_max - bname.len
	sb.write_string('\t${bname}_len' + ' '.repeat(bn_diff_len - 4) + ' = ${fbytes.len}\n')
	fbyte := fbytes[0]
	bnmae_line := '\t${bname}' + ' '.repeat(bn_diff_len) + ' = [u8(${fbyte}), '
	sb.write_string(bnmae_line)
	mut line_len := bnmae_line.len + 3
	for i := 1; i < fbytes.len; i++ {
		b := int(fbytes[i]).str()
		if line_len > 94 {
			sb.go_back(1)
			sb.write_string('\n\t\t')
			line_len = 8
		}
		if i == fbytes.len - 1 {
			sb.write_string(b)
			line_len += b.len
		} else {
			sb.write_string('${b}, ')
			line_len += b.len + 2
		}
	}
	sb.write_string(']!\n')
	return sb.str()
}

fn (context Context) bname_and_bytes(file string) !(string, []u8) {
	fname := os.file_name(file)
	fname_escaped := fname.replace_each(['.', '_', '-', '_'])
	byte_name := '${context.prefix}${fname_escaped}'.to_lower()
	fbytes := os.read_bytes(file) or { return error('Error: ${err.msg()}') }
	return byte_name, fbytes
}

fn (context Context) max_bname_len(bnames []string) int {
	mut max := 0
	for n in bnames {
		if n.len > max {
			max = n.len
		}
	}
	// Add 4 to max due to "_len" suffix
	return max + 4
}

fn main() {
	mut context := Context{}
	mut fp := flag.new_flag_parser(os.args[1..])
	fp.application('v bin2v')
	fp.version(tool_version)
	fp.description(tool_description)
	fp.arguments_description('FILE [FILE]...')
	context.show_help = fp.bool('help', `h`, false, 'Show this help screen.')
	context.module_name = fp.string('module', `m`, 'binary', 'Name of the generated module.')
	context.prefix = fp.string('prefix', `p`, '', 'A prefix put before each resource name.')
	context.write_file = fp.string('write', `w`, '', 'Write directly to a file with the given name.')
	if context.show_help {
		println(fp.usage())
		exit(0)
	}
	files := fp.finalize() or {
		eprintln('Error: ${err.msg()}')
		exit(1)
	}
	real_files := files.filter(it != 'bin2v')
	if real_files.len == 0 {
		println(fp.usage())
		exit(0)
	}
	context.files = real_files
	if context.write_file != '' && os.file_ext(context.write_file) !in ['.vv', '.v'] {
		context.write_file += '.v'
	}
	mut file_byte_map := map[string][]u8{}
	for file in real_files {
		bname, fbytes := context.bname_and_bytes(file) or {
			eprintln(err.msg())
			exit(1)
		}
		file_byte_map[bname] = fbytes
	}
	max_bname := context.max_bname_len(file_byte_map.keys())
	if context.write_file.len > 0 {
		mut out_file := os.create(context.write_file)!
		out_file.write_string(context.header())!
		for bname, fbytes in file_byte_map {
			out_file.write_string(context.file2v(bname, fbytes, max_bname))!
		}
		out_file.write_string(context.footer())!
	} else {
		print(context.header())
		for bname, fbytes in file_byte_map {
			print(context.file2v(bname, fbytes, max_bname))
		}
		print(context.footer())
	}
}
