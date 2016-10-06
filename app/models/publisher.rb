class Publisher < ApplicationRecord

  attr_encrypted :bitcoin_address, key: :encryption_key

  devise :timeoutable, :trackable

  # Normalizes attribute before validation and saves into other attribute
  phony_normalize :phone, as: :phone_normalized, default_country_code: "US"

  validates :bitcoin_address, bitcoin_address: true, presence: true, if: :should_validate_bitcoin_address?
  validates :email, email: { strict_mode: true }, presence: true
  validates :name, presence: true
  validates :phone, phony_plausible: true

  # publisher_id is a normalized identifier provided by ledger API
  # It is like base domain (eTLD + left part) but may include additional
  # formats to support more publishers.
  validates :publisher_id, presence: true

  # TODO: Show user normalized domain before they commit
  before_validation :normalize_publisher_id

  after_create :generate_verification_token

  def to_s
    publisher_id
  end

  def encryption_key
    Rails.application.secrets[:attr_encrypted_key]
  end

  private

  def generate_verification_token
    update_attribute(:verification_token, PublisherTokenRequester.new(self).perform)
  end

  def normalize_publisher_id
    require "faraday"
    self.publisher_id = PublisherDomainNormalizer.new(publisher_id).perform
  rescue Faraday::Error
    errors.add(:publisher_id, "can't be normalized because of an API error")
  end

  # This allows for blank bitcoin_address on first create, but
  # requires it on subsequent steps
  def should_validate_bitcoin_address?
    persisted?
  end
end