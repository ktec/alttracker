defmodule Cryptofolio.Web.TradeController do
  use Cryptofolio.Web, :controller

  alias Coherence.Config
  alias Cryptofolio.Dashboard

  import Canary.Plugs

  plug :load_and_authorize_resource, model: Cryptofolio.Dashboard.Trade, only: [:index, :new, :create, :show, :edit, :update, :delete]
  plug Coherence.Authentication.Session, [protected: true] when action in [:toggle_privacy]
  use Cryptofolio.Web.AuthorizationController

  def index(conn, _params) do
    user = conn.assigns[:current_user]

    show_user(conn, user)
  end

  def username(conn, %{ "username" => username }) do
    user = Dashboard.get_portfolio_by_username(username)

    show_user(conn, user)
  end

  def show_user(conn, user) do
    if user do
      current_user = conn.assigns[:current_user]
      owned = if current_user, do: current_user.id === user.id, else: false
      private = user.private_portfolio

      portfolio = Dashboard.get_portfolio(user)
      fiat_exchange = Dashboard.get_fiat_exchange(user)

      params = [portfolio: portfolio, fiat: fiat_exchange, owned: owned, private: private]
      case {owned, private} do
        {true, _} -> render(conn, "index.html", params)
        {false, false} -> render(conn, "index.html", params)
        {false, true} -> render(conn, "404.html")
      end
    else
      render(conn, "404.html")
    end
  end

  def new(conn, _params) do
    btc_price = Dashboard.get_coin_price("BTC")
    total_cost_btc = Decimal.div(Decimal.new(1), btc_price)
    changeset = Dashboard.change_trade(%Cryptofolio.Dashboard.Trade{ amount: 1 }, %{ cost: 1, total_cost: 1, total_cost_btc: total_cost_btc })

    case Dashboard.list_currencies() do
      currencies ->
        conn
        |> render("new.html", changeset: changeset, currencies: currencies, btc_price: btc_price)
    end
  end

  def create(conn, %{"trade" => trade_params}) do
    case Dashboard.create_user_trade(conn.assigns[:current_user], trade_params) do
      {:ok, _trade} ->
        conn
        |> put_flash(:info, "Trade created successfully.")
        |> redirect(to: trade_path(conn, :index))
      {:error, %Ecto.Changeset{} = changeset} ->
        currencies = Dashboard.list_currencies()
        btc_price = Dashboard.get_coin_price("BTC")

        render(conn, "new.html", changeset: changeset, currencies: currencies, btc_price: btc_price)
    end
  end

  def show(conn, %{"id" => id}) do
    trade = Dashboard.get_trade_with_currency!(id)
    fiat_exchange = Dashboard.get_fiat_exchange(conn.assigns[:current_user])

    render(conn, "show.html", trade: trade, fiat: fiat_exchange)
  end

  def edit(conn, %{}) do
    trade = conn.assigns[:trade]
    btc_price = Dashboard.get_coin_price("BTC")
    changeset = Dashboard.change_trade(trade)
    case Dashboard.list_currencies() do
      currencies ->
        conn
        |> render("edit.html", trade: trade, changeset: changeset, currencies: currencies, btc_price: btc_price)
    end
  end

  def update(conn, %{"trade" => trade_params}) do
    trade = conn.assigns[:trade]

    case Dashboard.update_trade(trade, trade_params) do
      {:ok, trade} ->
        conn
        |> put_flash(:info, "Trade updated successfully.")
        |> redirect(to: trade_path(conn, :show, trade))
      {:error, %Ecto.Changeset{} = changeset} ->
        case Dashboard.list_currencies() do
          currencies ->
            conn
            |> render("edit.html", trade: trade, changeset: changeset, currencies: currencies)
        end
    end
  end

  def toggle_privacy(conn, _params) do
    user = conn.assigns[:current_user]

    case Dashboard.toggle_privacy(user) do
      {:ok, user} ->
        apply(Config.auth_module, Config.update_login, [conn, user, [id_key: Config.schema_key]])

        conn
        |> put_flash(:info, "Portfolio is now " <> Cryptofolio.Web.TradeView.privacy_text(user.private_portfolio))
        |> redirect(to: trade_path(conn, :index))
    end
  end

  def delete(conn, %{}) do
    trade = conn.assigns[:trade]
    {:ok, _trade} = Dashboard.delete_trade(trade)

    conn
    |> put_flash(:info, "Trade deleted successfully.")
    |> redirect(to: trade_path(conn, :index))
  end
end
