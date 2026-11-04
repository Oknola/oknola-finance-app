module Oknola
  class QuickEntriesController < ApplicationController
    def new
      redirect_to new_transaction_path(nature: params[:kind] == "income" ? "inflow" : "outflow")
    end
  end
end
