require 'brcobranca'
require 'grape'
require 'aws-sdk-s3'

# Encapsulates all methods related to boletos
module BoletoApi
  def self.get_boleto(bank, values)
    clazz = Object.const_get("Brcobranca::Boleto::#{bank.camelize}")
    date_fields = %w[data_documento data_vencimento data_processamento]
    date_fields.each do |date_field|
      values[date_field] = Date.parse(values[date_field]) if values[date_field]
    end
    clazz.new(values)
  end

  # Verificar quais são os valores que podem ser recuperados das variáveis de ambiente
  # e quais são obrigatórios e os default de cada campo
  def self.defaults
    {
      # Valores armazenados em variaveis de ambiente
      agencia: ENV['AGENCIA'],
      conta_corrente: ENV['CONTA_CORRENTE'],
      nosso_numero: ENV['NOSSO_NUMERO'],
      documento_cedente: ENV['DOCUMENTO_CEDENTE'],
      cedente: ENV['CENDENTE'],
      cedente_endereco: ENV['CEDENTE_ENDERECO'],
      carteira: ENV['CARTEIRA'],
      aceite: ENV['ACEITE'],

      # Valores default hardcoded
      instrucao1: "Sr. Caixa:",
      instrucao2: "1) Não aceitar pagamento em cheque;",
      instrucao3: "2) Não aceitar mais de um pagamento com o mesmo boleto;",
      instrucao4: "3) Em caso de vencimento no fim de semana ou feriado, aceitar o pagamento até o primeiro dia",
      instrucao5: "útil após o vencimento.",
    }
  end

  # Cria um bucket no AWS S3
  def self.create_bucket(boleto)
    s3 = Aws::S3::Resource.new(region: 'us-east-1')
    bucket = s3.bucket("emprestae-boletos-#{boleto.sacado_documento}")
    bucket.create unless bucket.exists?

    bucket
  end

  # Faz o upload dos arquivos para o S3
  def self.cloud_upload(boleto, bucket)
    name = "boleto-#{rand(36**10).to_s(36)}.pdf"
    object = bucket.object(name)
    object.upload_stream do |write_stream|
      write_stream << boleto.to(:pdf)
    end

    object
  end

  # Rest api server
  class Server < Grape::API
    version 'v1', using: :header, vendor: 'Akretion'
    format :json
    prefix :api

    resource :boleto do
      desc 'Return a bolato image or pdf'
      # Available fields are listed here: https://github.com/kivanio/brcobranca/blob/master/lib/brcobranca/boleto/base.rb
      params do
        # requires :bank, type: String, desc: 'Bank'
        # requires :type, type: String, desc: 'Type: pdf|jpg|png|tif'
        requires :data, type: Hash, desc: 'Boleto data as a stringified json'
      end
      post do
        boleto = BoletoApi.get_boleto(ENV['BANCO'], BoletoApi.defaults.merge(params[:data]))
        
        if boleto.valid?
          bucket = BoletoApi.create_bucket(boleto)
          object = BoletoApi.cloud_upload(boleto, bucket)

          # Gera a resposta
          content_type 'application/json'
          {
            valor: boleto.valor,
            vencimento: boleto.data_vencimento,
            linha_digitavel: boleto.codigo_barras.linha_digitavel,
            url: object.public_url
          }

        else
          error!(boleto.errors.messages, 400)
        end
      end
    end
  end
end
