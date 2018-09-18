#!/usr/bin/env ruby

#
#   process_test_files.rb
#
#   Copyright 2016 Tony Stone
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#   Created by Tony Stone on 5/4/16.
#
require 'getoptlong'
require 'fileutils'
require 'pathname'

include FileUtils

#
# This ruby script will auto generate LinuxMain.swift and the +XCTest.swift extension files for Swift Package Manager on Linux platforms.
#
# See https://github.com/apple/swift-corelibs-xctest/blob/master/Documentation/Linux.md
#
def header(file_name)
  string = <<-eos
//
//  <FileName>
//  Queuer
//
//  The MIT License (MIT)
//
//  Copyright (c) 2017 - 2018 Fabrizio Brancati.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//
//
//  NOTE: This file was generated by generate_linux_tests.rb
//
//  Do NOT edit this file directly as it will be regenerated automatically when needed.
//

import XCTest
  eos

  string
  .sub('<FileName>', File.basename(file_name))
  .sub('<Date>', Time.now.to_s)
end

def create_extension_file(file_name, classes)
  extension_file = file_name.sub! '.swift', '+XCTest.swift'
  print 'Creating file: ' + extension_file + "\n"

  File.open(extension_file, 'w') do |file|
    file.write header(extension_file)
    file.write "\n"

    for class_array in classes
      file.write 'internal extension ' + class_array[0] + " {\n"
      file.write '    internal static var allTests: [(String, (' + class_array[0] + ") -> () throws -> Void)] {\n"
      file.write "        return [\n"

      class_count = class_array[1].size
      count = 0
      for func_name in class_array[1]
        count += 1

        file.write '            ("' + func_name + '", ' + func_name + (count == class_count ? ")\n" : "),\n")
      end

      file.write "        ]\n"
      file.write "    }\n"
      file.write "}\n"
    end
  end
end

def create_linux_main(tests_directory, all_test_sub_directories, files)
  file_name = tests_directory + '/LinuxMain.swift'
  print 'Creating file: ' + file_name + "\n"

  File.open(file_name, 'w') do |file|
    file.write header(file_name)
    file.write "\n"

    file.write "#if os(Linux) || os(FreeBSD)\n"
    for test_sub_directory in all_test_sub_directories.sort { |x, y| x <=> y }
      file.write '    @testable import ' + test_sub_directory + "\n"
    end
    file.write "\n"
    file.write "    XCTMain([\n"

    test_cases = []
    for classes in files
      for class_array in classes
        test_cases << class_array[0]
      end
    end

    cases_count = test_cases.size
    count = 0
    for test_case in test_cases.sort { |x, y| x <=> y }
      count += 1

      file.write '        testCase(' + test_case + (count == cases_count ? ".allTests)\n" : ".allTests),\n")
    end
    file.write "    ])\n"
    file.write "#endif\n"
  end
end

def parse_source_file(file_name)
  puts 'Parsing file: ' + file_name + "\n"

  classes = []
  current_class = nil
  in_if_linux = false
  in_else = false
  ignore = false

  #
  # Read the file line by line
  # and parse to find the class
  # names and func names
  #
  File.readlines(file_name).each do |line|
    if in_if_linux
      if /\#else/ =~ line
        in_else = true
        ignore = true
      elsif /\#end/ =~ line
          in_else = false
          in_if_linux = false
          ignore = false
      end
    elsif /\#if[ \t]+os\(Linux\)/ =~ line
        in_if_linux = true
        ignore = false
    end

    next if ignore
    # Match class or func
    match = line[/class[ \t]+[a-zA-Z0-9_]*(?=[ \t]*:[ \t]*XCTestCase)|func[ \t]+test[a-zA-Z0-9_]*(?=[ \t]*\(\))/, 0]
    if match
      if match[/class/, 0] == 'class'
        class_name = match.sub(/^class[ \t]+/, '')
        #
        # Create a new class / func structure
        # and add it to the classes array.
        #
        current_class = [class_name, []]
        classes << current_class
      else # Must be a func
        func_name = match.sub(/^func[ \t]+/, '')
        #
        # Add each func name the the class / func
        # structure created above.
        #
        current_class[1] << func_name
      end
    end
  end
  classes
end

#
# Main routine
#
#

tests_directory = 'Tests'

options = GetoptLong.new(['--tests-dir', GetoptLong::OPTIONAL_ARGUMENT])
options.quiet = true

begin
  options.each do |option, value|
    case option
    when '--tests-dir'
      tests_directory = value
    end
  end
  rescue GetoptLong::InvalidOption
end

all_test_sub_directories = []
all_files = []

Dir[tests_directory + '/*'].each do |sub_directory|
  next unless File.directory?(sub_directory)
  directory_has_classes = false
  Dir[sub_directory + '/*Test{s,}.swift'].each do |file_name|
    next unless File.file? file_name
    file_classes = parse_source_file(file_name)

    #
    # If there are classes in the
    # test source file, create an extension
    # file for it.
    #
    next unless file_classes.count.positive?
    create_extension_file(file_name, file_classes)
    directory_has_classes = true
    all_files << file_classes
  end

  if directory_has_classes
    all_test_sub_directories << Pathname.new(sub_directory).split.last.to_s
  end
end

#
# Last step is the create a LinuxMain.swift file that
# references all the classes and funcs in the source files.
#
if all_files.count.positive?
  create_linux_main(tests_directory, all_test_sub_directories, all_files)
end
# eof
