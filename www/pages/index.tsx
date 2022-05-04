import type { NextPage } from 'next';
import Head from 'next/head';
import Image from 'next/image';
import { ethers, BigNumber, providers } from 'ethers';
import { SellOrder } from 'rwtp';
import * as ethUtil from 'ethereumjs-util';
import * as sigUtil from '@metamask/eth-sig-util';
import { useRouter } from 'next/router';
import { useEffect, useState } from 'react';
import { PrismLight as SyntaxHighlighter } from 'react-syntax-highlighter';
import solidity from 'react-syntax-highlighter/dist/cjs/languages/prism/solidity';
import typescript from 'react-syntax-highlighter/dist/cjs/languages/prism/typescript';
import { KOVAN_CHAIN_ID, OPTIMISM_CHAIN_ID } from '../lib/constants';

SyntaxHighlighter.registerLanguage('solidity', solidity);
SyntaxHighlighter.registerLanguage('typescript', typescript);

const useCountdown = (targetDate: any) => {
  const countDownDate = new Date(targetDate).getTime();

  const [countDown, setCountDown] = useState(
    countDownDate - new Date().getTime()
  );

  useEffect(() => {
    const interval = setInterval(() => {
      setCountDown(countDownDate - new Date().getTime());
    }, 1000);

    return () => clearInterval(interval);
  }, [countDownDate]);

  return getReturnValues(countDown);
};

function useChain() {
  const [chain, setChain] = useState('');
  const [chainId, setChainId] = useState(NaN);

  useEffect(() => {
    if (!window.ethereum) return;
    const provider = new ethers.providers.Web3Provider(window.ethereum as any);
    provider.getNetwork().then((network) => {
      if (network.name == "homestead") network.name = "ethereum"
      setChain(network.name);
      setChainId(network.chainId)
    });
  });

  return [chain, chainId];
}

const getReturnValues = (countDown: any) => {
  // calculate time left
  const days = Math.floor(countDown / (1000 * 60 * 60 * 24));
  const hours = Math.floor(
    (countDown % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)
  );
  const minutes = Math.floor((countDown % (1000 * 60 * 60)) / (1000 * 60));
  const seconds = Math.floor((countDown % (1000 * 60)) / 1000);

  return [days, hours, minutes, seconds];
};

function encryptMessage(publicKey: string, message: string) {
  return ethUtil.bufferToHex(
    Buffer.from(
      JSON.stringify(
        sigUtil.encrypt({
          publicKey: publicKey,
          data: message,
          version: 'x25519-xsalsa20-poly1305',
        })
      ),
      'utf8'
    )
  );
}

async function switchNetwork(chainId: number) {
  if (!window.ethereum) return;
  const provider = new ethers.providers.Web3Provider(window.ethereum as any);
  if (chainId == 137) {
    await provider.send('wallet_addEthereumChain', [
      {
        chainId: "0x" + chainId.toString(16), // A 0x-prefixed hexadecimal string
        chainName: "Polygon Mainnet",
        nativeCurrency: {
          name: "Matic",
          symbol: "MATIC",
          decimals: 18,
        },
        rpcUrls: ["https://polygon-rpc.com"]
      }
    ]);
  } else if (chainId == 10) {
    await provider.send('wallet_addEthereumChain', [
      {
        chainId: "0x" + chainId.toString(16), // A 0x-prefixed hexadecimal string
        chainName: "Optimism",
        nativeCurrency: {
          name: "Ethereum",
          symbol: "ETH",
          decimals: 18,
        },
        rpcUrls: ["https://mainnet.optimism.io"]
      }
    ]);
  }
  await provider.send('wallet_switchEthereumChain', [
    { chainId: "0x" + chainId.toString(16) },
  ]);
}

const SUPPORTED_CHAIN_IDS = [10, 137];
const OPTIMISM_SELL_ORDER_ADDRESS = "0x1b1955f6732691b9d7FBC4F01FF28F640aA52940";
const POLYGON_SELL_ORDER_ADDRESS = "0x9fCcC594735639B6C18496d375a1C3675Cedd5d8";
const KOVAN_SELL_ORDER_ADDRESS = "0x4D2787E7C9B19Ec6C68734088767a39250476989";
const STICKERS_SELL_ORDER =
  process.env.NODE_ENV === 'production'
    ? OPTIMISM_SELL_ORDER_ADDRESS // production
    : KOVAN_SELL_ORDER_ADDRESS; // development

function StickerStore() {
  const [email, setEmail] = useState('');
  const [shippingAddress, setShippingAddress] = useState('');
  const [chain, chainId] = useChain();

  const DEFAULT_STAKE = 5;
  const DEFAULT_PRICE = 10;

  const router = useRouter();
  async function submitBuyOrder() {
    const provider = new ethers.providers.Web3Provider(window.ethereum as any);

    await provider.send('eth_requestAccounts', []); // <- this prompts user to connect metamask

    // If we're in development, switch to Kovan
    if (process.env.NODE_ENV !== 'production' && chain != 'optimism-kovan') {
      await provider.send('wallet_switchEthereumChain', [
        { chainId: KOVAN_CHAIN_ID },
      ]);
    }

    const signer = provider.getSigner();
    let sellOrderAddress: string;
    switch (chainId) {
      case 10:
        sellOrderAddress = OPTIMISM_SELL_ORDER_ADDRESS;
        break;
      case 137:
        sellOrderAddress = POLYGON_SELL_ORDER_ADDRESS;
        break;
      default:
        sellOrderAddress = KOVAN_SELL_ORDER_ADDRESS;
        break;
    }
    const sellOrder = new ethers.Contract(
      sellOrderAddress,
      SellOrder.abi,
      signer
    );

    // Encrypt the shipping details
    const encryptionPublicKey = 'EAYabfhy8OTaRcuTax5Q8zMBYadgrd3nf8haHJLHIwU='; // hard coding jacob's pubkey for now

    const encryptedMessage = encryptMessage(
      encryptionPublicKey,
      JSON.stringify({
        email: email,
        shippingAddress: shippingAddress,
      })
    );

    const result = await fetch('/api/upload', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        data: encryptedMessage,
      }),
    });
    const { cid } = await result.json();

    const erc20ABI = [
      'function approve(address spender, uint256 amount)',
      'function decimals() public view returns (uint8)',
    ];
    const token = await sellOrder.token();
    const erc20 = new ethers.Contract(token, erc20ABI, signer);
    const decimals = await erc20.decimals();

    const tokenTx = await erc20.approve(
      sellOrder.address,
      BigNumber.from(DEFAULT_PRICE + DEFAULT_STAKE).mul(
        BigNumber.from(10).pow(decimals)
      )
    );
    const tokenRcpt = await tokenTx.wait();
    if (tokenRcpt.status != 1) {
      console.log("Error approving tokens");
      return;
    }

    const orderTx = await sellOrder.submitOffer(
      BigNumber.from(DEFAULT_PRICE).mul(BigNumber.from(10).pow(decimals)),
      BigNumber.from(DEFAULT_STAKE).mul(BigNumber.from(10).pow(decimals)),
      'ipfs://' + cid
    );
    
    const orderRcpt = await orderTx.wait();
    if (orderRcpt.status != 1) {
      console.log("Error submitting order");
      return;
    }

    router.push('/orders/' + sellOrderAddress);
  }

  const [days, hours, minutes, seconds] = useCountdown('2022-05-09');

  return (
    <div className="bg-blue-50 p-4 pb-8">
      <div className="text-xs text-gray-500 pb-2">
        {chain && 'Network: ' + chain + ' '}
        (Currently only Metamask is supported due to{' '}
        <a
          className="underline"
          target={'_blank'}
          href="https://github.com/ethers-io/ethers.js/issues/1422"
        >
          this issue
        </a>
        )
      </div>
      <div className="bg-white border border-black rounded ">
        <div className="px-4 py-2 bg-gray-50 border-b border-black">
          <div className="font-mono text-xs pt-2">
            <div suppressHydrationWarning>
              {' '}
              Available for {days} days {hours} hours {minutes} minutes {seconds}{' '}
              seconds
            </div>
          </div>
          <div className="font-bold pb-2">Buy Stickers</div>
          <div className="text-sm pb-2">
            We'll deliver limited-edition stickers to your doorstep via the
            RWTP. You can trust that we'll deliver them to you, because we've
            staked <span className="text-blue-500 font-bold">20 USDC</span>. If
            the deal doesn't go through, we'll lose those sweet 20 bucks to the
            void.
          </div>
        </div>
        {SUPPORTED_CHAIN_IDS.includes(chainId as number) &&
          <div className="px-4 py-4">
            <label className="border flex flex-col mt-2">
              <div className="text-xs bg-gray-100 px-2 py-1">
                Shipping Address
              </div>
              <input
                type={'text'}
                className={'px-2 py-2'}
                name="address"
                placeholder="100 Saddle Point; San Fransokyo, CA 94112"
                onChange={(e) => setShippingAddress(e.target.value)}
              />
            </label>

            <label className="border flex flex-col mt-2">
              <div className="text-xs bg-gray-100 px-2 py-1">Email</div>
              <input
                type={'email'}
                className={'px-2 py-2'}
                placeholder="you@ethereum.org"
                onChange={(e) => setEmail(e.target.value)}
              />
              <div className="text-xs px-2 py-1 bg-gray-50 border-t">
                *Only used to contact you if something goes wrong, not to sign you
                up for an email list.
              </div>
            </label>

            <div className="flex flex-col sm:flex-row items-center justify-end mt-2">
              <div className="text-sm py-2 pr-2 items-center text-gray-700 ">
                The price is <span className="text-blue-500 font-bold">10 USDC</span> with
                a <span className="text-blue-500 font-bold">5 USDC</span> stake. Your stake will be returned
                if you confirm your delivery.
                {chainId == 137 && <p> <a className="text-blue-500 font-bold underline" href="https://buy.moonpay.com/?defaultCurrencyCode=usdc_polygon" target="_blank">Buy USDC</a>.</p>}
                {chainId == 10 && <p> <a className="text-blue-500 font-bold underline" href="https://global.transak.com" target="_blank">Buy USDC</a>.</p>}
              </div>
              <button
                onClick={() => submitBuyOrder().catch(console.error)}
                className="ml-2 rounded bg-blue-500 text-white border border-blue-700 px-4 py-2 text-sm disabled:opacity-50 transition-all"
                disabled={!email || !shippingAddress}
              >
                Send 15 USDC
              </button>
            </div>
          </div>}
        {!chainId &&
          <div className="px-4 py-4">
            <div className="font-bold pb-2">Connect to Metamask</div>
            <div className="text-sm pb-2">
              Making purchases on RWTP requires a Metamask wallet on a supported network. 
              You can install the Metamask Chrome extension <a className='underline text-blue-500 font-bold' href="https://metamask.io/download/" target="_blank">here</a>.
            </div>
          </div>}
        {!!chainId && !SUPPORTED_CHAIN_IDS.includes(chainId as number) &&
          <div className="px-4 py-4">
            <div className="font-bold pb-2">Unsupported Network</div>
            <div className="text-sm pb-2">
              This product is currently unavailable on the <span className="text-blue-500 font-bold">{chain}</span> network.
              Set your Metamask to a supported network:
            </div>
            <div className="flex flex-row items-center gap-2">
              <button
                className='className="ml-2 rounded bg-blue-500 text-white border border-blue-700 px-4 py-2 text-sm disabled:opacity-50 transition-all"'
                onClick={() => switchNetwork(137)}
              >
                Polygon
              </button>
              <button
                className='className="ml-2 rounded bg-blue-500 text-white border border-blue-700 px-4 py-2 text-sm disabled:opacity-50 transition-all"'
                onClick={() => switchNetwork(10)}
              >
                Optimism
              </button>
            </div>
          </div>}
      </div>
    </div>
  );
}

const Home: NextPage = () => {
  return (
    <div>
      <Head>
        <title>RWTP - Real World Trade Protocol</title>
        <meta
          name="description"
          content="A way of shipping real world goods on ethereum"
        />
        <link rel="icon" href="/favicon.ico" />

        {/* Twitter */}
        <meta name="twitter:card" content="summary" key="twcard" />
        <meta
          name="twitter:creator"
          content={'strangemoodorg'}
          key="twhandle"
        />

        {/* Open Graph */}
        <meta
          property="og:site_name"
          content={'Strangemood'}
          key="ogsitename"
        />
        <meta
          property="og:title"
          content={'RWTP - Real World Trade Protocol'}
          key="ogtitle"
        />
        <meta
          property="og:description"
          content={'A way to buy and sell real-world goods on Ethereum'}
          key="ogdesc"
        />
      </Head>

      <div className="max-w-4xl mx-auto flex flex-col pb-24 ">
        <div className="m-4 border-b-2 border-black">
          <div className="pb-4 flex justify-between">
            <a className="font-mono flex underline" href="/">
              <Image width={24} height={24} src="/smallrwtp.png" />
              rwtp
            </a>

            <div className="flex ">
              <a
                className="font-mono flex underline ml-2"
                href="https://discord.gg/evqa7Evuw6"
              >
                discord
              </a>

              <a
                className="font-mono flex underline ml-2"
                href="/whitepaper.pdf"
              >
                whitepaper
              </a>

              <a
                className="font-mono flex underline ml-2"
                href="https://github.com/flaque/rwtp"
              >
                github
              </a>
            </div>
          </div>

          <Image src={'/Header.png'} layout="responsive" height={1} width={2} />
        </div>
        <div className="px-4 mt-4">
          <h1 className="text-2xl font-bold mb-1 items-center flex">
            Real World Trade Protocol{' '}
            <span className="bg-blue-50 ml-2 p-1 rounded font-mono text-blue-600 text-sm">
              v0.1.0
            </span>
          </h1>
          <p className="mt-2 ">
            The Real World Trade Protocol <code>(RWTP)</code> is a peer-to-peer
            way to buy and sell real-world goods on Ethereum. Use RWTP to build
            automated companies, low-cost futures markets, decentralized
            ecommerce platforms, sell moderately cool stickers, or otherwise
            program the economy.
          </p>

          <div className="mt-4">
            <StickerStore />
          </div>
        </div>
      </div>
    </div>
  );
};

export default Home;
