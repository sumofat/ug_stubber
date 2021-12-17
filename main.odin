package main 
import fmt "core:fmt"
import utf8 "core:unicode/utf8"
import strings "core:strings"
import os "core:os"
import tokenizer "tokenizer"

GLStubifyReturnTypes :: enum{
    gl_returntype_void,
    gl_returntype_uint,
    gl_returntype_int,
    gl_returntype_glbool,
    gl_returntype_gluint,
    gl_returntype_glubyte,
    gl_returntype_glenum,
    gl_returntype_nullpointer,
    gl_returntype_glsync,//is a pointer to a struct
}

GLParam :: struct{
	type : GLStubifyReturnTypes,
	name : string,
}

GLReturnType :: struct{
    flags : u32,
    token : tokenizer.Token,
    is_pointer : bool,
}

GLReturnTypeFlags :: enum{
    gl_returntype_flag_const = 0x01,
}

GLHeaderDataBlockType :: enum{
    glheader_data_func_sig,
    glheader_data_func_impl,
    glheader_data_func_other,
}

GLHeaderDataBlock :: struct{
    type : GLHeaderDataBlockType,
    tokens : [dynamic]tokenizer.Token,
}

GLHeaderData :: struct{
    header_data_block : [dynamic]GLHeaderDataBlock,
}

parse_gl_header :: proc(input : string) -> GLHeaderData{
	using fmt
	using tokenizer

	result : GLHeaderData
	result.header_data_block  = make([dynamic]GLHeaderDataBlock) 
	tokenizer_ : Tokenizer
	tokenizer := &tokenizer_
	tokenizer.src = input
	w : int
	tokenizer.at,w = current_rune(tokenizer^)
	tokens : [dynamic]Token = make([dynamic]Token)
	prev_token : Token

	is_parsing : bool = true

	//printf(tokenizer.src)
	for is_parsing{
		token := get_token(tokenizer)
		append(&tokens,token)

		if is_comment_start(prev_token,token){
			max_iterations_allowed := max(int)
			for i := 0;i < max_iterations_allowed;i += i{
				token = get_token(tokenizer)
				if is_comment_end(prev_token,token){
					break
				}
				prev_token = token
			}
			continue
		}

		if token.type == .Identifier{
			if token.data == "GL_API" && prev_token.data != "define"{
				block : GLHeaderDataBlock
				block.type = .glheader_data_func_sig
                block.tokens = make([dynamic]Token)
                //beggining of function definition.
                append(&block.tokens,token)
                for{
                	token = get_token(tokenizer)
                	append(&block.tokens,token)
					if token.type == .SemiColon{
						break
					}
					prev_token = token
                }
                append(&result.header_data_block,block)
			}
		}

		if token.type == .EndOfStream{
			break
		}else if tokenizer.offset >= len(tokenizer.src){
			break
		}

		prev_token = token
	}
	return result
}

get_return_string :: proc(type : GLStubifyReturnTypes)-> string
{
    result : string
    switch(type)
    {
        case .gl_returntype_void:{
            result = "\treturn;\n"
        }
        case .gl_returntype_uint:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_int:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_glbool:{
            result = "\treturn false;\n"
        }
        case .gl_returntype_glubyte:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_gluint:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_glenum:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_nullpointer:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_glsync:{
            result = "\treturn 0;\n"
        }
        case:{
        	assert(false)
        }
    }
    return result;
}

get_return_type :: proc(data : string) -> GLStubifyReturnTypes{
	return_type : GLStubifyReturnTypes
	if "void" == data{
		return_type = .gl_returntype_void
	}else if "GLuint" == data{
		return_type = .gl_returntype_gluint
	}else if data == "int"{
        return_type = .gl_returntype_int;
    }else if data == "GLboolean"{
        return_type = .gl_returntype_glbool;
    }else if data == "GLenum"{
        return_type = .gl_returntype_glenum;
    }else if data == "GLubyte"{
        return_type = .gl_returntype_glubyte;
    }else if data == "GLenum"{
        return_type = .gl_returntype_glenum;
    }
    return return_type
}

get_ug_call_sig :: proc(out_builder : ^strings.Builder,types : []GLParam){
	using strings
	using fmt

	write_string_builder(out_builder,"unigraph_call_")
	param_count_string := tprintf("%d",len(types))
	write_string_builder(out_builder,param_count_string)
	write_rune_builder(out_builder,'(')

	//write parameters
	global_func_id := get_id_for_function_call()	
	write_string_builder(out_builder,global_func_id)
	write_rune_builder(out_builder,',')

	//write_string_builder(out_builder,file_location)
//	write_rune_builder(out_builder,',')

	for param in types{
		write_rune_builder(out_builder,',')
		global_gl_type_id := int(param.type)///gl_get_global_type_id(param)
		write_string_builder(out_builder,global_gl_type_id)
		write_rune_builder(out_builder,',')
		write_string_builder(out_builder,param.name)
	}
	write_rune_builder(out_builder,')')
	write_rune_builder(out_builder,';')

}

lex_the_tokens :: proc(out_builder : ^strings.Builder,input_gl_h : string){
	using strings
	using fmt
	using tokenizer

	return_type_info : GLReturnType  = {};
	header_data := parse_gl_header(input_gl_h)
	next_token : Token
	prev_token : Token
	prev_prev_token : Token

	current_param_types : [dynamic]GLParam = make([dynamic]GLParam)

	for  i := 0;i< len(header_data.header_data_block) - 1;i+=1{
		block := header_data.header_data_block[i]
		is_start_params : bool
		is_next_param : bool
		param_count : int
		param : GLParam
		for j := 0;j < len(block.tokens);j+=1{
			t := block.tokens[j]

			if j + 1 < len(block.tokens) - 1{
				next_token = block.tokens[(j+1)]
			}

			if t.type == .OpenParen{
				is_deprecated : bool 
				if prev_token.data == "OPENGLES_DEPRECATED"{
					is_deprecated = true
					open_paren_count := 0
					close_paren_count := 0
					k := j
					for {
						tt := block.tokens[k]
						if tt.type == .OpenParen{
							open_paren_count += 1
						}else if tt.type == .CloseParen{
							close_paren_count += 1
						}

						if open_paren_count != close_paren_count{
							k += 1
						}else{
							j = k
							break
						}
					}
					continue
				}


				//Todo(Ray):add to string output here
				write_rune_builder(out_builder,'(')
				
				if is_deprecated == false{
					is_start_params = true
				}

				//printf(to_string(out_builder^))

			}else if t.type == .CloseParen{
				//add string output
				write_rune_builder(out_builder,')')
				//printf(to_string(out_builder^))
			}else if t.type == .SemiColon{
				// NOTE(Ray Garner): This is the end of the signature
                //we throw away the semicolon and add create our braces
                //and return type here.
                //Yostr func_stub = CreateStringFromLiteral("\n{\n",&func_sig_temp_arena);
                //GLStubifyReturnTypes return_type = {};

				return_type : GLStubifyReturnTypes

                // NOTE(Ray Garner): If its a pointer typee we will always return a null pointer type is equivalent to zero.
                if return_type_info.is_pointer || "GLsync" == return_type_info.token.data{
                	return_type = .gl_returntype_void
                }else{

                	return_type = get_return_type(return_type_info.token.data)
                	/*
                	if "void" == return_type_info.token.data{
                		return_type = .gl_returntype_void
                	}else if "GLuint" == return_type_info.token.data{
                		return_type = .gl_returntype_gluint
                	}else if return_type_info.token.data == "int"{
                        return_type = .gl_returntype_int;
                    }else if return_type_info.token.data == "GLboolean"{
                        return_type = .gl_returntype_glbool;
                    }else if return_type_info.token.data == "GLenum"{
                        return_type = .gl_returntype_glenum;
                    }else if return_type_info.token.data == "GLubyte"{
                        return_type = .gl_returntype_glubyte;
                    }else if return_type_info.token.data == "GLenum"{
                        return_type = .gl_returntype_glenum;
                    }*/
                }
                
                func_stub : string = "\n{\n"
                write_string_builder(out_builder,func_stub)
                //printf(to_string(out_builder^))
                write_string_builder(out_builder,get_ug_call_sig(out_builder,current_param_types[:]))
                write_rune_builder(out_builder,'\n')
                write_string_builder(out_builder,get_return_string(return_type))
                //printf(to_string(out_builder^))
                write_string_builder(out_builder,"}\n\n")
                //printf(to_string(out_builder^))
                return_type_info.is_pointer = false; 
                return_type_info.flags = 0;
			}else if t.type == .Comma{
				write_rune_builder(out_builder,',')
				//printf(to_string(out_builder^))
			}else if t.type == .Asterisk{
				write_rune_builder(out_builder,'*')
				//printf(to_string(out_builder^))
			}else if t.type == .Identifier{
				if "GL_API" == prev_prev_token.data &&
					prev_token.data == "const"{
						return_type_info.token = t
						return_type_info.flags = u32(GLReturnTypeFlags.gl_returntype_flag_const)
						if next_token.type == .Asterisk{
							return_type_info.is_pointer = true
						}
				}else if "GL_API" == prev_token.data{
					if next_token.type == .Asterisk{
						return_type_info.is_pointer = true
					}
					return_type_info.token = t
				}

				if "OPENGLES_DEPRECATED" != t.data{
					if is_start_params {
						if param_count % 2 == 0{
							param.type = get_return_type(t.data)
						}else if param_count % 3 == 0{
							param.name = t.data
							append(&current_param_types,param)
						}
						
					}
					write_string_builder(out_builder,t.data)
					//printf(to_string(out_builder^))
					write_rune_builder(out_builder,' ')
					//printf(to_string(out_builder^))
				}
			}
			prev_prev_token = prev_token
			prev_token = t
		}
		//printf(to_string(out_builder^))
	}
}

main ::  proc(){
	using fmt
	using strings
	println("UG STUBBER INIT")

	input_gl_h := string(#load("headers_to_stub/gl.h"))
	input_gl_ext_h := string(#load("headers_to_stub/glext.h"))

	out_builder_ := make_builder_none()
	out_builder := &out_builder_


	lex_the_tokens(out_builder,input_gl_h)
	gl_h_string := to_string(out_builder^)
	print(gl_h_string)


	os.write_entire_file("gl.h",(transmute([]u8)gl_h_string)[:])

	out_builder_ext := make_builder_none()
	lex_the_tokens(&out_builder_ext,input_gl_ext_h)

	print(to_string(out_builder_ext))



}
