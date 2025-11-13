// FractalEA_Improved.mq5
// Improved Fractal Expert Advisor using 5 K-lines detection, risk management, position checking, and trend filtering

// Input parameters
input double LotSize = 0.1; // Lot size
input double TakeProfit = 50; // Take profit in points
input double StopLoss = 50; // Stop loss in points
input int RiskPercentage = 1; // Risk percentage
input int Slippage = 3; // Slippage in points

// Global variables
int ticket = 0;

// Function to detect fractals
bool isFractalUp(int index) {
    return High[index] > High[index + 1] && High[index] > High[index - 1];
}

bool isFractalDown(int index) {
    return Low[index] < Low[index + 1] && Low[index] < Low[index - 1];
}

// Function for risk management
double CalculateLotSize(double riskPercentage) {
    double accountRisk = AccountBalance() * riskPercentage / 100;
    double lotSize = accountRisk / (StopLoss * Point * 10);
    return NormalizeDouble(lotSize, 2);
}

// Check open positions
bool HasOpenPosition() {
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if (OrderSelect(i, SELECT_BY_POS) && OrderType() == OP_BUY) {
            return true;
        }
    }
    return false;
}

// Function for trend filtering
int GetTrendDirection() {
    double maCurrent = iMA(NULL, 0, 14, 0, MODE_SMA, PRICE_CLOSE, 0);
    double maPrevious = iMA(NULL, 0, 14, 0, MODE_SMA, PRICE_CLOSE, 1);
    return (maCurrent > maPrevious) ? 1 : -1; // 1 = uptrend, -1 = downtrend
}

// Main trading function
void OnTick() {
    if (HasOpenPosition()) return; // Check for open positions
    int trend = GetTrendDirection(); // Get trend direction
    
    // Detect fractals
    for (int i = 5; i < Bars - 5; i++) {
        if (isFractalUp(i) && trend == 1) {
            // Buy logic
            double lotSize = CalculateLotSize(RiskPercentage);
            ticket = OrderSend(Symbol(), OP_BUY, lotSize, Ask, Slippage, 0, 0, "Fractal EA", 0, 0, clrGreen);
            if (ticket < 0) Print("Error opening buy order: ", GetLastError());
        }
        if (isFractalDown(i) && trend == -1) {
            // Sell logic
            double lotSize = CalculateLotSize(RiskPercentage);
            ticket = OrderSend(Symbol(), OP_SELL, lotSize, Bid, Slippage, 0, 0, "Fractal EA", 0, 0, clrRed);
            if (ticket < 0) Print("Error opening sell order: ", GetLastError());
        }
    }
}