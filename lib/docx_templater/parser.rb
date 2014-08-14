# encoding: UTF-8

# docx_templater -- Converts Word docx files into html or LaTeX via the kramdown syntax
# Copyright (C) 2014 pl0o0f (florent@cryph.net) and don't forget GPL
#
# This software has been inspired from:
# = https://github.com/jawspeak/ruby-docx-templater
# = https://github.com/michaelfranzl/docx_converter
# 
# It is a complete rewrite however but credits are credits and everybody should be thanked for their contribution
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
# 
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

module DocxTemplater
  class Replacer
    def initialize(options)
      @data = options[:data]
      @output_dir = options[:output_dir]
      @docx_filepath = options[:inputfile]
      @out_filepath = options[:outfile]
      
      @zipfile = Zip::ZipFile.new(@docx_filepath)
    end
    
    def replace
      garbage = Array.new
      document_xml = unzip_read("word/document.xml")
      footnotes_xml = unzip_read("word/footnotes.xml")
      
      content = Nokogiri::XML(document_xml)
      footnotes = Nokogiri::XML(footnotes_xml)
     
      garbage += parse_content(content.elements)
      garbage += parse_content(footnotes.elements)

      garbage.map(&:unlink)
     
      zip_write(@out_filepath, content, footnotes) 
    end
    
    private
    
    def unzip_read(zip_path)
      file = @zipfile.find_entry(zip_path)
      contents = ""
      file.get_input_stream do |f|
        contents = f.read
      end
      return contents
    end

    def zip_write(zip_path, content, footnotes)
      buffer = Zip::OutputStream.write_buffer do |out|
        @zip_file.entries.each do |e|
          unless ['document.xml', 'footnotes.xml'].include?(e.name)
            out.put_next_entry(e.name)
            out.write e.get_input_stream.read
          end
        end

        out.put_next_entry('document.xml')
        out.write content.to_xml(:indent => 0).gsub("\n","")

        out.put_next_entry('footnotes.xml')
        out.write footnotes.to_xml(:indent => 0).gsub("\n","")
      end

      File.open(zip_path, "w") {|f| f.write(buffer.string) }
    end

 
    def expand_loop(nd, key, data)
      garbage = Array.new
      if !data.has_key?(key)
        end_row = nd
        until /#END_ROW:#{key.upcase.to_s}#/.match(end_row.text.to_s)
          garbage.append(end_row)
          end_row = end_row.next
        end
        return garbage + [end_row]
      elsif data[key].empty?
        end_row = nd
        until /#END_ROW:#{key.upcase.to_s}#/.match(end_row.text.to_s)
          garbage.append(end_row)
          end_row = end_row.next
        end
        return garbage + [end_row]
      else
        rows = Array.new
        start_row = nd
        end_row = nd.next
        until /#END_ROW:#{key.upcase.to_s}#/.match(end_row.text.to_s)
          rows.append(end_row)
          end_row = end_row.next
        end
        garbage = [start_row, end_row]
        data[key].each do |element|
          rows.each do |nd| 
            case nd.text.to_s
            when /#BEGIN_ROW:([A-Z0-9_]+)#/
              new_key = $1.downcase.to_sym
              garbage += expand_loop(nd, new_key, element)
            when /#END_ROW:([A-Z0-9_]+)#/
              garbage += [nd]
            else
              garbage += [nd]
              new_node = nd.dup
              nd.add_next_sibling(new_node)
              subst_content(new_node, element)
            end
          end
        end
        return garbage.uniq
      end
    end

    def parse_content(elements, data=@data)
      garbage = Array.new
      elements.each do |nd|
        case nd.name
        when "tr"
          case nd.text.to_s
          when /#BEGIN_ROW:([A-Z0-9_]+)#/
            key = $1.downcase.to_sym
            garbage += expand_loop(nd, key, data)
          else # it's a normal table row
            garbage += parse_content(nd.elements, data)
          end
        when "t" # It's a leaf that contains data to replace
          subst_content(nd, data) 
        else # it's neither a leaf or a loop so let's process it
          garbage += parse_content(nd.elements, data)
        end
      end
      return garbage.uniq
    end

    def subst_content(nd, data)
      inner = nd.inner_html
      @keys = nd.text.scan(/\$([A-Z0-9_]+)\$/).map(&:first).map(&:downcase).map(&:to_sym)
      @keys.each do |key|
        if data.has_key?(key)
          value = data[key]
          inner.gsub!("$#{key.to_s.upcase}$", safe(value))
        end
      end
      if !@keys.empty?
        nd.inner_html = inner
      end
    end

    def safe(text)
      text.to_s
    end
    
  end
end
