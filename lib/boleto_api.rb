require 'brcobranca'
require 'grape'
require 'aws-sdk'

module BoletoApi

  def self.get_boleto(bank, values)
   clazz = Object.const_get("Brcobranca::Boleto::#{bank.camelize}")
   date_fields = %w[data_documento data_vencimento data_processamento]
   date_fields.each do |date_field|
      values[date_field] = Date.parse(values[date_field]) if values[date_field]
    end
    clazz.new(values)
  end

  # Cria um bucket no AWS S3
  def self.create_bucket(boleto)
    s3 = Aws::S3::Resource.new(region: 'us-east-1')
    bucket = s3.bucket("emprestae-boletos-#{boleto.sacado_documento}")
    bucket.create unless bucket.exists?

    return bucket
  end

  # Faz o upload dos arquivos para o S3
  def self.cloud_upload(boleto, bucket)
    name = "boleto-#{rand(36**10).to_s(36)}.pdf"
    object = bucket.object(name)
    object.upload_stream do |write_stream|
      write_stream << boleto.to(:pdf)
    end

    return object
  end

  class Server < Grape::API
    version 'v1', using: :header, vendor: 'Akretion'
    format :json
    prefix :api

    resource :boleto do
      desc 'Return a bolato image or pdf'
      # Os campos do boleto estão listados aqui: https://github.com/kivanio/brcobranca/blob/master/lib/brcobranca/boleto/base.rb
      params do
        requires :bank, type: String, desc: 'Bank'
        requires :type, type: String, desc: 'Type: pdf|jpg|png|tif'
        requires :data, type: Hash, desc: 'Boleto data as a stringified json'
      end
      post do
        boleto = BoletoApi.get_boleto(params[:bank], params[:data])
        if boleto.valid?
          bucket = BoletoApi.create_bucket(boleto)
          object = BoletoApi.cloud_upload(boleto, bucket)

          # Gera a resposta
          content_type "application/json"
          {
            valor: boleto.valor,
            vencimento: boleto.data_vencimento,
            linha_digitavel: boleto.codigo_barras.linha_digitavel,
            url: object.public_url,
          }

        else
          error!(boleto.errors.messages, 400)
        end
      end
    end
  end
end
