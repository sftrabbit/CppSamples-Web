require 'net/http'
require 'uri'

module CppSamples
	DEFAULT_SAMPLES_DIR = '_samples'
	COMMENT_REGEX = /^\/\/\s*(.+)$/

	class SamplePage < Jekyll::Page
		def initialize(site, sample)
			@site = site
			@base = site.source
			@dir = File.dirname(sample.path)
			@name = "#{File.basename(sample.path)}.html"

			process(@name)
			read_yaml(File.join(@base, ''), '_sample.html')

			self.data['sample'] = sample
		end
	end

	class SamplesGenerator < Jekyll::Generator
		def generate(site)
			index = site.pages.detect { |page| page.url == '/index.html' }

			samples_dir = site.config['samples_dir'] || DEFAULT_SAMPLES_DIR
			samples_tree = CppSamples::build_samples_tree(samples_dir)

			index.data['sample_categories'] = samples_tree

			samples_tree.each do |category, sections|
				sections.each do |section, samples|
					samples.each do |sample|
						site.pages << SamplePage.new(site, sample)
					end
				end
			end
		end
	end

	class Section
		attr_accessor :title, :path

		def initialize(title_file_name)
			@path = File.dirname(title_file_name)

			title_file = File.new(title_file_name, 'r')
			@title = title_file.readline.chomp
		end

		def to_liquid
			return {'title' => @title, 'path' => @path}
		end
	end

	class Sample
		attr_accessor :title, :code, :description, :path, :contributors

		def initialize(sample_file_name)
			sample_file = File.new(sample_file_name, 'r')

			@path = file_name_to_path(sample_file_name)

			sample_contents = strip_blank_lines(sample_file.readlines)

			@title = extract_title(sample_contents)
			description_lines = extract_description(sample_contents)
			description_start = sample_contents.length - description_lines.length
			@description = description_lines.join
			code_lines = strip_blank_lines(sample_contents[1..description_start-1])
			@code = code_lines.join

			@contributors = get_contributors(sample_file_name)
		end

		def to_liquid
			{
				'title' => @title,
				'code' => @code,
				'description' => @description,
				'contributors' => @contributors,
				'path' => @path
			}
		end

		private def file_name_to_path(file_name)
			file_name_parts = file_name.split('/')[-3..-1]
			file_name_parts[2] = File.basename(file_name_parts[2], '.*')
			file_name_parts.join('/')
		end

		private def extract_title(lines)
			header = lines[0]
			header_match = COMMENT_REGEX.match(header)

			unless header_match
				raise "invalid header line in sample"
			end

			header_match[1]
		end

		private def extract_description(lines)
			description = []
			line_index = lines.length - 1
			while match = COMMENT_REGEX.match(lines[line_index])
				description.unshift("#{match[1]}\n")
				line_index -= 1
			end
			description
		end

		private def strip_blank_lines(lines)
			lines.join("").strip.split("\n").map {|line| "#{line}\n" }
		end

		private def get_contributors(file_name)
			emails = nil
			Dir.chdir('_samples') do
				gitlog_output = `git log --format="format:%ae" -- #{@path}.cpp`
				emails = gitlog_output.split("\n")
			end

			contributors = []

			emails.each do |email|
				search_uri = URI.parse("https://api.github.com/search/users?q=#{email}+in:email&per_page=1")
				search_response = Net::HTTP.get_response(search_uri)
				search_result = JSON.parse(search_response.body)
				user = search_result['items'][0]

				contributors << {
					'name' => user['login'],
					'image' => user['avatar_url'],
					'url' => user['html_url']
				}
			end

			contributors
		end
	end

	def self.build_samples_tree(samples_dir)
		sections = build_dir(samples_dir)

		sections.inject({}) do |tree, section|
			categories = build_dir(section.path)

			tree[section] = categories.inject({}) do |tree_section, category|
				tree_section[category] = collect_samples(category.path)
				tree_section
			end

			tree
		end
	end

	def self.build_dir(dir)
		subdir_title_file_names = Dir.glob("#{dir}/*/TITLE")

		subdir_title_file_names.inject([]) do |sections, subdir_title_file_name|
			sections << Section.new(subdir_title_file_name)
		end
	end

	def self.collect_samples(dir)
		sample_file_names = Dir.glob("#{dir}/*.cpp")
		sample_file_names.inject([]) do |samples, sample_file_name|
			samples << Sample.new(sample_file_name)
		end
	end
end
