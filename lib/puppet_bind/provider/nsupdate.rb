# ex: syntax=ruby si sw=2 ts=2 et
require 'tempfile'

module PuppetBind
  module Provider

    def self.nsupdate_provider(type)
    end

    module NsUpdate

      def exists?
        !(query.empty?)
      end

      def create
        update do |file|
          accio(file)
        end
      end

      def destroy
        update do |file|
          destructo(file)
        end
      end

      def flush
        return if @properties.empty?
        update do |file|
          accio(file)
          destructo(file)
        end
      end

      def ttl
        query.first[:ttl]
      end

      def ttl=(ttl)
        @properties[:ttl] = ttl
      end

    private

      def update(&block)
        file = Tempfile.new('dns_rr-nsupdate-')
        file.write "server #{server}\n"
        file.write "zone #{zone}\n" unless zone.nil?
        yield file
        file.write "send\n"
        file.close
        if keyed?
          nsupdate('-y', tsig_param, file.path)
        elsif keyfile?
          nsupdate('-k', kfile, file.path)
        else
          nsupdate(file.path)
        end
        file.unlink
      end

      def accio(file)
        rrdata_adds.each do |datum|
          file.write "update add #{name}. #{resource[:ttl]} #{rrclass} #{type} #{maybe_quote(type, datum)}\n"
        end
      end

      def destructo(file)
        rrdata_deletes.each do |datum|
          file.write "update delete #{name}. #{ttl} #{rrclass} #{type} #{maybe_quote(type, datum)}\n"
        end
      end

      def quoted_type?(type)
        %w(TXT SPF).include?(type)
      end

      def maybe_quote(type, datum)
        quoted_type?(type) ? "\"#{datum}\"" : datum
      end

      def maybe_unquote(type, datum)
        quoted_type?(type) ? datum.gsub(/^\"(.*)\"$/, '\1') : datum
      end

      def rrdata_adds
        resource[:ensure] === :absent ? [] : newdata - rrdata
      end

      def rrdata_deletes
        resource[:ensure] === :absent ? rrdata : (type === 'SOA' ? [] : rrdata - newdata)
      end

      def server
        resource[:server]
      end

      def zone
        resource[:zone]
      end

      def query_section
        resource[:query_section]
      end

      def keyname
        resource[:keyname]
      end

      def kfile
        resource[:keyfile]
      end

      def keyfile?
        !kfile.nil?
      end

      def hmac
        resource[:hmac]
      end

      def secret
        resource[:secret]
      end

      def keyed?
        !secret.nil?
      end

      def tsig_param
        "#{hmac}:#{keyname}:#{secret}"
      end

      def query
        unless @query
          if keyed?
            dig_text = dig("@#{server}", '+noall', '+nosearch', '+norecurse', "+#{query_section}", name, type, '-c', rrclass, '-y', tsig_param)
          else
            dig_text = dig("@#{server}", '+noall', '+nosearch', '+norecurse', "+#{query_section}", name, type, '-c', rrclass)
          end
          @query = dig_text.lines.map do |line|
            linearray = line.chomp.split(/\s+/, 5)
            {
              :name    => linearray[0],
              :ttl     => linearray[1],
              :rrclass => linearray[2],
              :type    => linearray[3],
              :rrdata  => maybe_unquote(linearray[3], linearray[4])
            }
          end.select do |record|
            record[:name] == "#{name}."
          end
        end
        @query
      end

    end
  end
end
