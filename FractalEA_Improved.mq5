//+------------------------------------------------------------------+
//|                                          FractalEA_Improved.mq5 |
//|                                   改进版分型指标Expert Advisor    |
//|                              使用标准5根K线分型检测和完整风险管理  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://github.com/scnchxh-ai/scnchxh"
#property version   "2.00"
#property description "完整的改进版分型指标EA，包含5根K线分型检测、风险管理、趋势过滤等高级功能"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| 输入参数 - 基本交易设置                                            |
//+------------------------------------------------------------------+
input group "===== 基本交易参数 ====="
input double   InpFixedLot = 0.1;              // 固定手数（当风险模式=0时使用）
input bool     InpUseRiskManagement = true;    // 使用风险管理模式
input double   InpRiskPercent = 1.0;           // 账户风险百分比（每笔交易）
input double   InpStopLossPoints = 500;        // 止损点数
input double   InpTakeProfitPoints = 1000;     // 止盈点数
input int      InpMaxPositions = 1;            // 最大同时持仓数量

//+------------------------------------------------------------------+
//| 输入参数 - 分型检测设置                                            |
//+------------------------------------------------------------------+
input group "===== 分型检测参数 ====="
input int      InpFractalBars = 5;             // 分型检测K线数量（标准=5）
input bool     InpVerifyFractal = true;        // 启用分型验证（确保数据有效）
input int      InpMinFractalStrength = 10;     // 最小分型强度（点数）

//+------------------------------------------------------------------+
//| 输入参数 - 趋势过滤                                                |
//+------------------------------------------------------------------+
input group "===== 趋势过滤参数 ====="
input bool     InpUseTrendFilter = true;       // 启用趋势过滤
input int      InpMAPeriod = 50;               // 移动平均线周期
input ENUM_MA_METHOD InpMAMethod = MODE_SMA;   // 移动平均线类型
input ENUM_APPLIED_PRICE InpMAPrice = PRICE_CLOSE; // 应用价格

//+------------------------------------------------------------------+
//| 输入参数 - 交易时段限制                                            |
//+------------------------------------------------------------------+
input group "===== 交易时段设置 ====="
input bool     InpUseTimeFilter = false;       // 启用交易时段过滤
input int      InpStartHour = 8;               // 开始交易小时（服务器时间）
input int      InpEndHour = 20;                // 结束交易小时（服务器时间）

//+------------------------------------------------------------------+
//| 输入参数 - 日志和调试                                              |
//+------------------------------------------------------------------+
input group "===== 日志和调试 ====="
input bool     InpEnableDebugLog = true;       // 启用调试日志
input bool     InpEnableStats = true;          // 启用统计信息
input int      InpMagicNumber = 888888;        // 魔术号码（识别EA订单）

//+------------------------------------------------------------------+
//| 全局变量                                                           |
//+------------------------------------------------------------------+
CTrade         trade;                          // 交易对象
CPositionInfo  positionInfo;                   // 持仓信息对象
CAccountInfo   accountInfo;                    // 账户信息对象
CSymbolInfo    symbolInfo;                     // 交易品种信息对象

int            maHandle;                       // 移动平均线指标句柄
double         maBuffer[];                     // 移动平均线缓冲区

// 统计变量
int            totalTrades = 0;                // 总交易次数
int            winningTrades = 0;              // 盈利交易次数
int            losingTrades = 0;               // 亏损交易次数
double         totalProfit = 0;                // 总盈利
datetime       lastTradeTime = 0;              // 上次交易时间

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // 设置魔术号码
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(Symbol());
    trade.SetDeviationInPoints(50);
    
    // 初始化交易品种信息
    if(!symbolInfo.Name(_Symbol))
    {
        Print("错误: 无法初始化交易品种信息");
        return(INIT_FAILED);
    }
    symbolInfo.Refresh();
    
    // 创建移动平均线指标
    if(InpUseTrendFilter)
    {
        maHandle = iMA(_Symbol, _Period, InpMAPeriod, 0, InpMAMethod, InpMAPrice);
        if(maHandle == INVALID_HANDLE)
        {
            Print("错误: 无法创建移动平均线指标");
            return(INIT_FAILED);
        }
        ArraySetAsSeries(maBuffer, true);
    }
    
    // 输出初始化信息
    Print("==========================================");
    Print("分型EA已成功初始化");
    Print("交易品种: ", _Symbol);
    Print("时间周期: ", EnumToString(_Period));
    Print("风险管理: ", InpUseRiskManagement ? "启用" : "禁用");
    Print("风险百分比: ", InpRiskPercent, "%");
    Print("止损点数: ", InpStopLossPoints);
    Print("止盈点数: ", InpTakeProfitPoints);
    Print("趋势过滤: ", InpUseTrendFilter ? "启用" : "禁用");
    Print("交易时段过滤: ", InpUseTimeFilter ? "启用" : "禁用");
    Print("==========================================");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // 释放指标句柄
    if(maHandle != INVALID_HANDLE)
        IndicatorRelease(maHandle);
    
    // 输出统计信息
    if(InpEnableStats && totalTrades > 0)
    {
        Print("==========================================");
        Print("交易统计信息:");
        Print("总交易次数: ", totalTrades);
        Print("盈利交易: ", winningTrades);
        Print("亏损交易: ", losingTrades);
        Print("胜率: ", (totalTrades > 0 ? DoubleToString((double)winningTrades/totalTrades*100, 2) : "0"), "%");
        Print("总盈利: ", DoubleToString(totalProfit, 2));
        Print("==========================================");
    }
    
    Print("分型EA已卸载，原因: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // 检查是否有足够的K线数据
    if(Bars(_Symbol, _Period) < 100)
    {
        if(InpEnableDebugLog)
            Print("等待更多K线数据...");
        return;
    }
    
    // 更新交易品种信息
    if(!symbolInfo.RefreshRates())
    {
        if(InpEnableDebugLog)
            Print("无法刷新交易品种报价");
        return;
    }
    
    // 检查交易时段
    if(!IsWithinTradingHours())
    {
        if(InpEnableDebugLog)
            Print("当前不在交易时段内");
        return;
    }
    
    // 检查持仓数量限制
    if(CountOpenPositions() >= InpMaxPositions)
    {
        if(InpEnableDebugLog)
            Print("已达到最大持仓数量: ", InpMaxPositions);
        return;
    }
    
    // 检测分型信号
    int signal = DetectFractalSignal();
    
    if(signal == 1) // 看涨分型
    {
        if(InpEnableDebugLog)
            Print("检测到看涨分型信号");
        
        // 检查趋势过滤
        if(InpUseTrendFilter && !IsBullishTrend())
        {
            if(InpEnableDebugLog)
                Print("趋势过滤: 不是上涨趋势，跳过买入信号");
            return;
        }
        
        // 开多单
        OpenBuyPosition();
    }
    else if(signal == -1) // 看跌分型
    {
        if(InpEnableDebugLog)
            Print("检测到看跌分型信号");
        
        // 检查趋势过滤
        if(InpUseTrendFilter && !IsBearishTrend())
        {
            if(InpEnableDebugLog)
                Print("趋势过滤: 不是下跌趋势，跳过卖出信号");
            return;
        }
        
        // 开空单
        OpenSellPosition();
    }
}

//+------------------------------------------------------------------+
//| 检测分型信号（使用5根K线标准方法）                                  |
//| 返回: 1=看涨分型, -1=看跌分型, 0=无信号                            |
//+------------------------------------------------------------------+
int DetectFractalSignal()
{
    // 确保有足够的K线数据（至少5根）
    if(Bars(_Symbol, _Period) < InpFractalBars + 2)
        return 0;
    
    // 检查bar[2]作为分型中心点（标准5根K线分型）
    int centerBar = 2;
    
    // 数据验证
    if(InpVerifyFractal)
    {
        double high2 = iHigh(_Symbol, _Period, centerBar);
        double low2 = iLow(_Symbol, _Period, centerBar);
        
        if(high2 <= 0 || low2 <= 0)
        {
            if(InpEnableDebugLog)
                Print("数据验证失败: 无效的K线数据");
            return 0;
        }
    }
    
    // 检测看涨分型（底分型）
    // bar[2]的最低点应该是5根K线中最低的
    if(IsFractalUp(centerBar))
    {
        // 验证分型强度
        if(InpMinFractalStrength > 0)
        {
            double strength = CalculateFractalStrength(centerBar, true);
            if(strength < InpMinFractalStrength * _Point)
            {
                if(InpEnableDebugLog)
                    Print("分型强度不足: ", strength/_Point, " 点");
                return 0;
            }
        }
        
        return 1; // 看涨分型信号
    }
    
    // 检测看跌分型（顶分型）
    // bar[2]的最高点应该是5根K线中最高的
    if(IsFractalDown(centerBar))
    {
        // 验证分型强度
        if(InpMinFractalStrength > 0)
        {
            double strength = CalculateFractalStrength(centerBar, false);
            if(strength < InpMinFractalStrength * _Point)
            {
                if(InpEnableDebugLog)
                    Print("分型强度不足: ", strength/_Point, " 点");
                return 0;
            }
        }
        
        return -1; // 看跌分型信号
    }
    
    return 0; // 无信号
}

//+------------------------------------------------------------------+
//| 检测看涨分型（底分型）- 使用5根K线标准方法                          |
//| bar[2]的最低点是中心点，应该低于前后各2根K线                       |
//+------------------------------------------------------------------+
bool IsFractalUp(int centerBar)
{
    double low0 = iLow(_Symbol, _Period, centerBar - 2);
    double low1 = iLow(_Symbol, _Period, centerBar - 1);
    double low2 = iLow(_Symbol, _Period, centerBar);      // 中心点
    double low3 = iLow(_Symbol, _Period, centerBar + 1);
    double low4 = iLow(_Symbol, _Period, centerBar + 2);
    
    // bar[2]的最低点应该是5根K线中最低的
    return (low2 < low0 && low2 < low1 && low2 < low3 && low2 < low4);
}

//+------------------------------------------------------------------+
//| 检测看跌分型（顶分型）- 使用5根K线标准方法                          |
//| bar[2]的最高点是中心点，应该高于前后各2根K线                       |
//+------------------------------------------------------------------+
bool IsFractalDown(int centerBar)
{
    double high0 = iHigh(_Symbol, _Period, centerBar - 2);
    double high1 = iHigh(_Symbol, _Period, centerBar - 1);
    double high2 = iHigh(_Symbol, _Period, centerBar);    // 中心点
    double high3 = iHigh(_Symbol, _Period, centerBar + 1);
    double high4 = iHigh(_Symbol, _Period, centerBar + 2);
    
    // bar[2]的最高点应该是5根K线中最高的
    return (high2 > high0 && high2 > high1 && high2 > high3 && high2 > high4);
}

//+------------------------------------------------------------------+
//| 计算分型强度（中心点与周围K线的价格差异）                           |
//+------------------------------------------------------------------+
double CalculateFractalStrength(int centerBar, bool isUpFractal)
{
    double strength = 0;
    
    if(isUpFractal)
    {
        double centerLow = iLow(_Symbol, _Period, centerBar);
        double avgHigh = 0;
        
        // 计算周围4根K线的平均最低价
        for(int i = -2; i <= 2; i++)
        {
            if(i == 0) continue; // 跳过中心点
            avgHigh += iLow(_Symbol, _Period, centerBar + i);
        }
        avgHigh /= 4;
        
        strength = avgHigh - centerLow; // 价格差异
    }
    else
    {
        double centerHigh = iHigh(_Symbol, _Period, centerBar);
        double avgLow = 0;
        
        // 计算周围4根K线的平均最高价
        for(int i = -2; i <= 2; i++)
        {
            if(i == 0) continue; // 跳过中心点
            avgLow += iHigh(_Symbol, _Period, centerBar + i);
        }
        avgLow /= 4;
        
        strength = centerHigh - avgLow; // 价格差异
    }
    
    return strength;
}

//+------------------------------------------------------------------+
//| 检查是否在交易时段内                                              |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    if(!InpUseTimeFilter)
        return true;
    
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    
    int currentHour = timeStruct.hour;
    
    if(InpStartHour <= InpEndHour)
    {
        // 正常时段，例如 8:00 - 20:00
        return (currentHour >= InpStartHour && currentHour < InpEndHour);
    }
    else
    {
        // 跨天时段，例如 20:00 - 8:00
        return (currentHour >= InpStartHour || currentHour < InpEndHour);
    }
}

//+------------------------------------------------------------------+
//| 检查是否为上涨趋势                                                |
//+------------------------------------------------------------------+
bool IsBullishTrend()
{
    if(!InpUseTrendFilter || maHandle == INVALID_HANDLE)
        return true;
    
    // 复制MA数据
    if(CopyBuffer(maHandle, 0, 0, 3, maBuffer) <= 0)
    {
        if(InpEnableDebugLog)
            Print("无法复制MA缓冲区数据");
        return false;
    }
    
    // 当前价格高于MA，且MA向上
    double currentPrice = symbolInfo.Bid();
    return (currentPrice > maBuffer[0] && maBuffer[0] > maBuffer[1]);
}

//+------------------------------------------------------------------+
//| 检查是否为下跌趋势                                                |
//+------------------------------------------------------------------+
bool IsBearishTrend()
{
    if(!InpUseTrendFilter || maHandle == INVALID_HANDLE)
        return true;
    
    // 复制MA数据
    if(CopyBuffer(maHandle, 0, 0, 3, maBuffer) <= 0)
    {
        if(InpEnableDebugLog)
            Print("无法复制MA缓冲区数据");
        return false;
    }
    
    // 当前价格低于MA，且MA向下
    double currentPrice = symbolInfo.Ask();
    return (currentPrice < maBuffer[0] && maBuffer[0] < maBuffer[1]);
}

//+------------------------------------------------------------------+
//| 统计当前持仓数量（只统计本EA的订单）                               |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    int total = PositionsTotal();
    
    for(int i = 0; i < total; i++)
    {
        if(positionInfo.SelectByIndex(i))
        {
            if(positionInfo.Symbol() == _Symbol && 
               positionInfo.Magic() == InpMagicNumber)
            {
                count++;
            }
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| 计算交易手数                                                      |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double lotSize = InpFixedLot;
    
    if(InpUseRiskManagement)
    {
        // 基于风险百分比计算手数
        double accountBalance = accountInfo.Balance();
        double riskMoney = accountBalance * InpRiskPercent / 100.0;
        
        // 计算每点价值
        double tickSize = symbolInfo.TickSize();
        double tickValue = symbolInfo.TickValue();
        double pointValue = tickValue;
        
        if(tickSize > 0)
            pointValue = tickValue / tickSize * _Point;
        
        // 计算手数
        if(InpStopLossPoints > 0 && pointValue > 0)
        {
            lotSize = riskMoney / (InpStopLossPoints * pointValue);
        }
    }
    
    // 标准化手数
    double minLot = symbolInfo.LotsMin();
    double maxLot = symbolInfo.LotsMax();
    double lotStep = symbolInfo.LotsStep();
    
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    if(InpEnableDebugLog)
        Print("计算的手数: ", lotSize);
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| 开多单                                                            |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double lotSize = CalculateLotSize();
    double ask = symbolInfo.Ask();
    double stopLoss = 0;
    double takeProfit = 0;
    
    // 计算止损和止盈
    if(InpStopLossPoints > 0)
        stopLoss = ask - InpStopLossPoints * _Point;
    
    if(InpTakeProfitPoints > 0)
        takeProfit = ask + InpTakeProfitPoints * _Point;
    
    // 规范化价格
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    takeProfit = NormalizeDouble(takeProfit, _Digits);
    
    // 执行开仓
    if(trade.Buy(lotSize, _Symbol, ask, stopLoss, takeProfit, "Fractal EA Buy"))
    {
        Print("成功开多单: 手数=", lotSize, ", 价格=", ask, 
              ", 止损=", stopLoss, ", 止盈=", takeProfit);
        
        totalTrades++;
        lastTradeTime = TimeCurrent();
    }
    else
    {
        Print("开多单失败: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| 开空单                                                            |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
    double lotSize = CalculateLotSize();
    double bid = symbolInfo.Bid();
    double stopLoss = 0;
    double takeProfit = 0;
    
    // 计算止损和止盈
    if(InpStopLossPoints > 0)
        stopLoss = bid + InpStopLossPoints * _Point;
    
    if(InpTakeProfitPoints > 0)
        takeProfit = bid - InpTakeProfitPoints * _Point;
    
    // 规范化价格
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    takeProfit = NormalizeDouble(takeProfit, _Digits);
    
    // 执行开仓
    if(trade.Sell(lotSize, _Symbol, bid, stopLoss, takeProfit, "Fractal EA Sell"))
    {
        Print("成功开空单: 手数=", lotSize, ", 价格=", bid, 
              ", 止损=", stopLoss, ", 止盈=", takeProfit);
        
        totalTrades++;
        lastTradeTime = TimeCurrent();
    }
    else
    {
        Print("开空单失败: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Trade事件处理函数（用于统计）                                      |
//+------------------------------------------------------------------+
void OnTrade()
{
    if(!InpEnableStats)
        return;
    
    // 检查最近关闭的订单
    if(HistorySelect(lastTradeTime, TimeCurrent()))
    {
        int total = HistoryDealsTotal();
        
        for(int i = 0; i < total; i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            
            if(ticket > 0)
            {
                long dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
                
                if(dealMagic == InpMagicNumber)
                {
                    long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
                    
                    // 只统计平仓订单
                    if(dealEntry == DEAL_ENTRY_OUT)
                    {
                        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                        totalProfit += profit;
                        
                        if(profit > 0)
                            winningTrades++;
                        else if(profit < 0)
                            losingTrades++;
                        
                        if(InpEnableDebugLog)
                            Print("订单关闭: 盈利=", profit, ", 总盈利=", totalProfit);
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+