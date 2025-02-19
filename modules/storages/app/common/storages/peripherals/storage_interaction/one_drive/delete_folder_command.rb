# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2023 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Storages
  module Peripherals
    module StorageInteraction
      module OneDrive
        class DeleteFolderCommand
          def self.call(storage:, location:)
            new(storage).call(location:)
          end

          def initialize(storage)
            @storage = storage
            @uri = storage.uri
          end

          def call(location:)
            Util.using_admin_token(@storage) do |http|
              response = http.delete("/v1.0/drives/#{@storage.drive_id}/items/#{location}")

              data = ::Storages::StorageErrorData.new(source: self.class, payload: response)

              case response.status
              when 200..299
                # The service returns a 204 with an empty body
                ServiceResult.success
              when 401
                ServiceResult.failure(result: :unauthorized,
                                      errors: ::Storages::StorageError.new(code: :unauthorized, data:))
              when 404
                ServiceResult.failure(result: :not_found,
                                      errors: ::Storages::StorageError.new(code: :not_found, data:))
              when 409
                ServiceResult.failure(result: :conflict,
                                      errors: ::Storages::StorageError.new(code: :conflict, data:))
              else
                ServiceResult.failure(result: :error,
                                      errors: ::Storages::StorageError.new(code: :error, data:))
              end
            end
          end
        end
      end
    end
  end
end
